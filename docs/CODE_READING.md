# CODE_READING.md — コードリーディングガイド

> このプロジェクトを初めて読む人が、どこから読めば全体を把握できるかを示すガイド。
> 仕様の一次情報は `docs/DESIGN.md`。

## 全体構成

```
slot-relay/
├── api/                     予約 API 本体（Rails 8.1・API モード）★ここが主役
│   ├── app/
│   │   ├── controllers/
│   │   │   ├── application_controller.rb      エラーコード → HTTP ステータスの対応表
│   │   │   ├── health_controller.rb            /health /ready
│   │   │   ├── docs_controller.rb              /openapi.json /docs
│   │   │   ├── concerns/public_api.rb          CORS ヘッダと許可 Origin 検証
│   │   │   └── v1/
│   │   │       ├── public/                     公開 API（無認証）
│   │   │       └── admin/                      管理 API（X-Admin-Key）
│   │   ├── models/
│   │   │   ├── booking_type.rb                 予約メニュー
│   │   │   ├── weekly_availability.rb          曜日別受付時間
│   │   │   ├── availability_override.rb        特定日の受付変更
│   │   │   ├── reservation.rb                  予約（状態遷移・キャンセルトークン）
│   │   │   └── concerns/wall_clock_time.rb     time カラムを壁時計時刻として扱う
│   │   ├── services/
│   │   │   ├── availability_calculator.rb      ★空き枠計算（中核 1）
│   │   │   ├── reservations/creator.rb         ★予約確定・二重予約防止（中核 2）
│   │   │   ├── reservations/canceller.rb       キャンセル
│   │   │   ├── reservations/rescheduler.rb     日時変更（管理 API）
│   │   │   ├── google_calendar/client.rb       Google Calendar API ラッパ（OAuth）
│   │   │   ├── google_calendar/null_client.rb  未連携時のダミー（local/test のみ）
│   │   │   ├── google_calendar/unavailable_client.rb  本番の未連携時。使うと 502 にする
│   │   │   ├── google_oauth/authorization.rb   同意画面の URL と state の署名
│   │   │   ├── google_oauth/callback.rb        認可コード → refresh token の交換
│   │   │   ├── google_oauth/setup_session.rb   設定画面の短期セッションと CSRF
│   │   │   ├── google_setup_page.rb            設定画面の HTML（api_only なので文字列で組む）
│   │   │   ├── google_calendar_selection.rb    選んだカレンダーを予約メニューへ保存
│   │   │   ├── booking_types/upsert.rb         予約メニューの登録・更新
│   │   │   ├── turnstile_verifier.rb           Cloudflare Turnstile
│   │   │   ├── origin_allow_list.rb            プリフライト用の Origin 集合
│   │   │   ├── google_event_presenter.rb       Google 予定の件名・説明
│   │   │   ├── openapi_document.rb             OpenAPI 3.1 ドキュメント（手書き）
│   │   │   └── service_result.rb               サービスクラスの戻り値
│   │   ├── serializers/                        JSON 表現（camelCase）
│   │   └── mailers/ + views/                   予約者・管理者向けメール
│   ├── lib/slot_relay.rb                       ★設定と外部依存の差し替えポイント
│   ├── config/
│   │   ├── routes.rb
│   │   └── initializers/
│   │       ├── rack_attack.rb                  レートリミット
│   │       ├── timestamptz.rb                  datetime → timestamptz
│   │       └── slot_relay.rb                   起動時の設定チェック
│   ├── db/migrate/                             ★排他制約は 20260730000006
│   └── test/                                   ユニット / ユースケース / 同時実行
├── web/                     予約フォームの参照実装（Next.js 15）
│   ├── lib/bookingApi.ts                       公開 API のクライアント
│   ├── components/BookingForm.tsx               日付 → 時間 → 入力 → 完了
│   ├── components/CancelPanel.tsx               キャンセル画面
│   └── test/                                   ユニット / 画面遷移
└── docs/
```

## 読み進める順序

1. **`docs/DESIGN.md`** — 何を作っているか（§1 プロダクト定義、§3.2 空き枠計算、§3.3 二重予約防止）
2. **`docs/MILESTONE.md`** — 何をどこまでやりたいか（決定の経緯は `docs/plans/`）
3. **`api/db/migrate/20260730000006_create_reservations.rb`** —
   二重予約を防ぐ排他制約。この設計を理解しないと予約処理が読めない
4. **`api/app/services/availability_calculator.rb`** — 空き枠計算。手順がそのままコメントにある
5. **`api/app/services/reservations/creator.rb`** — 予約確定の流れ（仮確保 → 直前確認 → 予定作成）
6. **`api/config/routes.rb` → `api/app/controllers/v1/`** — API の入口
7. **`api/lib/slot_relay.rb`** — 環境変数と Google クライアントの差し替え口
8. **`web/components/BookingForm.tsx`** — サイト側が公開 API をどう使うか

## 主要な概念・用語

| 用語 | 意味 |
| --- | --- |
| 予約メニュー（booking type） | 1 サイト・1 相談種別ぶんの予約設定。公開 API では `slug` で参照する |
| 枠（slot） | 予約できる時間の単位。`durationMinutes` 刻みで受付時間から生成する |
| 受付時間（weekly availability） | 曜日別の営業時間。**壁時計時刻**（予約メニューのタイムゾーン） |
| オーバーライド（availability override） | 特定日の休業・時間変更。曜日別設定を**置き換える** |
| 仮確保（pending） | 予約 POST の最初に作る 5 分間の押さえ。同時リクエストを DB で直列化するため |
| Busy 時間 | Google FreeBusy API が返す「予定が入っている区間」。件名・内容は取得しない |
| Google 連携（GoogleConnection） | 管理者の Google アカウント 1 件。refresh token を暗号化して保存する単一行 |
| 空き判定カレンダー / 登録先カレンダー | 前者は予定があれば枠を外すカレンダー（複数）、後者は予約の予定を作るカレンダー（1 つ）。設定画面から選ぶ |
| バッファ | 枠の前後に確保する空き時間。占有区間は `[start - before, end + after)` |
| キャンセルトークン | 確認メールに載せる生のシークレット。DB にはハッシュのみ保存 |
| Idempotency-Key | 予約 POST の必須ヘッダ。再送で二重予約にならないようにする |

## テストの地図

| ファイル | 何を担保するか |
| --- | --- |
| `api/test/models/reservation_test.rb` | 排他制約（重なり・隣接・状態別）、キャンセルトークンのハッシュ化 |
| `api/test/models/wall_clock_time_test.rb` | `time` カラムが `Time.zone` でずれない（回帰テスト） |
| `api/test/models/booking_type_test.rb` | slug・タイムゾーン・所要時間の検証、予約がある場合の削除拒否 |
| `api/test/services/availability_calculator_test.rb` | 空き枠計算の全条件（曜日・休業・最短受付・上限日・Busy・バッファ・pending） |
| `api/test/services/reservations/creator_test.rb` | 予約確定・Idempotency-Key・Turnstile・Google 失敗時の枠解放 |
| `api/test/services/reservations/canceller_test.rb` | キャンセルと Google 予定削除、削除失敗時の扱い |
| `api/test/services/reservations/rescheduler_test.rb` | 日時変更と失敗時のロールバック |
| `api/test/services/turnstile_verifier_test.rb` | Turnstile の成功・失敗・障害時（fail closed） |
| `api/test/controllers/` | HTTP ステータス・CORS・Origin 検証・レートリミット・OpenAPI の整合 |
| `api/test/mailers/mailers_test.rb` | 文面・タイムゾーン表記・キャンセル URL の出し分け |
| `api/test/models/google_connection_test.rb` | refresh token の暗号化・単一行の維持・復号失敗時の扱い |
| `api/test/services/google_oauth/` | 認可 URL・state の署名と失効・コード交換・設定画面セッションと CSRF |
| `api/test/services/google_calendar_selection_test.rb` | カレンダー選択の保存（部分失敗でロールバック） |
| `api/test/controllers/v1/admin/google_*_test.rb` | 連携フローの認証境界・CSRF・画面表示（トークンを出さないこと） |
| `api/test/integration/booking_flow_test.rb` | **ユースケース**: 登録 → 空き枠 → 予約 → 照会 → キャンセル |
| `api/test/integration/google_connection_flow_test.rb` | **ユースケース**: 連携 → カレンダー選択 → 空き枠に反映 |
| `api/test/integration/double_booking_test.rb` | **同時実行**: 実スレッド・別コネクションでの二重予約防止 |
| `web/test/bookingApi.test.ts` | API クライアント（Idempotency-Key、エラー変換） |
| `web/test/bookingFlow.test.tsx` | **画面遷移**: 日付 → 時間 → 入力 → 完了、枠が埋まった場合の巻き戻し |

テストの実行:

```bash
cd api && bin/rails test        # Rails（176 件）
cd web && npm test              # Next.js（15 件）
```

## よくある変更のレシピ

- **新しい公開エンドポイントを足す**: `config/routes.rb` に追加 → `app/controllers/v1/public/` に
  `BaseController` を継承したコントローラを作る（Origin の解決元が違う場合は `allowed_origins` を上書き）
  → `app/serializers/` に JSON 表現を足す → `app/services/openapi_document.rb` の `paths` に追記
- **予約メニューの設定項目を足す**: マイグレーション → `BookingType` に検証 →
  `BookingTypes::Upsert::ATTRIBUTE_MAP` に camelCase の対応を追加 → `BookingTypeSerializer` →
  `OpenapiDocument`（`BookingTypeInput` / `AdminBookingType`）
- **空き枠の条件を足す**: `AvailabilityCalculator` に手順を追加し、`DESIGN.md §3.2` の手順一覧も直す
- **メール文面を変える**: `app/views/guest_mailer/` `app/views/admin_mailer/`（text テンプレートのみ）
- **エラーコードを足す**: `ApplicationController::ERROR_STATUSES` に追加 → `DESIGN.md §3.6` の表を直す
- **環境変数を足す**: `lib/slot_relay.rb` の `Configuration` と `build_config` →
  `api/.env.example` → `docs/DEPLOY.md`
