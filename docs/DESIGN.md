# DESIGN.md — slot-relay 設計

> プロダクト仕様・アーキテクチャの**一次情報**。他ドキュメントからは「DESIGN §7.4」の形で §番号で参照する。
> 意思決定・経緯は本ファイルではなく `docs/plans/` の plan に残す。

## 1. プロダクト定義

**何を作るか** — Google カレンダーと連携する予約 API サーバー。

**誰のためか** — 現時点では作者 1 人（Google アカウント 1 つ）。複数の自社サイトから同じ API を使う。

**解く課題** — 予約フォームをサイトごとに実装すると、「空き枠の計算」と「二重予約の防止」という
一番壊れやすいロジックが重複する。そこだけを API として切り出し、画面は各サイトが自由に作る。

```
genba-tsunagu.jp の予約フォーム
        ↓ API
予約 API サーバー（slot-relay）
        ↓
Google Calendar
```

API サーバーの責務は次の 4 点に限定する。**予約画面は API の責務に含めない。**

1. 予約可能時間の管理
2. Google カレンダーを考慮した空き枠の計算
3. 二重予約を防止した予約登録
4. Google カレンダーへの予定作成

## 2. アーキテクチャ

### 2.1 システム構成

| ディレクトリ | 役割 |
| --- | --- |
| `api/` | 予約 API 本体（Ruby on Rails 8.1・API モード）。**これがプロダクト** |
| `web/` | 予約フォームの**参照実装**（Next.js 15）。本番デプロイ対象ではない |
| `docs/` | ドキュメント |

`web/` は「公開 API だけで予約画面が成立する」ことを示し、画面遷移を E2E で検証するために置く。
実際の予約画面は各サイト（genba-tsunagu.jp など）が自前のデザインで実装する。

Coolify 上のリソースは次の 2 つだけ。Web アプリ・Redis・ワーカーは作らない。

| リソース | 役割 |
| --- | --- |
| `booking-api` | REST API、Google Calendar 連携、メール送信 |
| `booking-postgres` | 予約メニュー、受付時間、予約データ |

### 2.2 ホスティング・環境（local / staging / production）

| 環境 | 用途 | URL |
| --- | --- | --- |
| local | 開発 | api: `http://localhost:3001` / web: `http://localhost:3000` |
| staging | なし（MVP では用意しない） | — |
| production | 本番 | `https://booking-api.genba-tsunagu.jp` |

API ドメインは独立させ、genba-tsunagu.jp のデプロイと分離する。手順は `docs/DEPLOY.md`。

### 2.3 技術的な制約・前提

| 項目 | 採用技術 |
| --- | --- |
| API | Ruby on Rails 8.1（`--api` モード） |
| 言語 | Ruby 3.3 |
| DB | PostgreSQL 16（`btree_gist` 拡張が必須） |
| 参照実装 UI | Next.js 15（App Router）・React 19・TypeScript |
| Google 認証 | サービスアカウント（一般ユーザー向け OAuth は実装しない） |
| Bot 対策 | Cloudflare Turnstile |
| レートリミット | rack-attack |
| メール | ActionMailer + SMTP |
| API 仕様 | OpenAPI 3.1（手書き）+ Swagger UI |
| ホスティング | Coolify |

制約・前提:

- **PostgreSQL 固有機能に依存する。** 二重予約の防止に `EXCLUDE USING gist` と `tstzrange` を使うため、
  他の RDBMS へは移植できない（§3.3）。
- **`datetime` カラムは `timestamptz`。** 排他制約が `tstzrange(start_at, end_at)` を使うため、
  タイムゾーンなしの `timestamp` だと暗黙キャストが `STABLE` 扱いになり GiST インデックスを作れない
  （`config/initializers/timestamptz.rb`）。
- **`time` カラムはタイムゾーン変換の対象外**（`time_zone_aware_types = [:datetime]`）。
  受付時間の `start_time` / `end_time` は「予約メニューのタイムゾーンにおける壁時計時刻」であり、
  読み出し時の `Time.zone` に応じてずれてはならない。
- **Rails の暗号化 credentials は使わない。** 秘密はすべて環境変数に置く（`config/master.key` を
  イメージへ同梱しないため）。その代わり production では `SECRET_KEY_BASE` が必須。
- **ワーカーを持たない。** メール送信は予約確定と同じリクエスト内で行い、失敗はログに記録する（§3.5）。
- **レートリミットのカウンタはプロセスのメモリ上**（`ActiveSupport::Cache::MemoryStore`）。
  単一コンテナ・単一プロセス運用を前提とした割り切り（`docs/SECURITY.md`）。

## 3. 主要機能

### 3.1 予約メニュー（booking type）

サイトから使う予約設定のかたまり。`slug` で公開 API から参照する。

```json
{
  "name": "無料相談",
  "slug": "genba-tsunagu-consultation",
  "durationMinutes": 60,
  "timeZone": "Asia/Tokyo",
  "minimumNoticeMinutes": 1440,
  "bookingWindowDays": 30,
  "bufferBeforeMinutes": 0,
  "bufferAfterMinutes": 0,
  "allowedOrigins": ["https://genba-tsunagu.jp"],
  "weeklyAvailability": [{ "dayOfWeek": 1, "startTime": "10:00", "endTime": "18:00" }],
  "availabilityOverrides": [{ "date": "2026-08-13", "isAvailable": false }]
}
```

- 同じ API に複数のメニューを登録でき、サイトごと・相談種別ごとに分けられる
  （`genba-tsunagu-consultation` / `kaizen-works-consultation` / `online-meeting` …）。
- `status: inactive` にすると公開 API から見えなくなる（404）。受付を止めるときはこれを使う。
- 削除は予約が 1 件もない場合のみ許可する（履歴を失わないため）。
- `availabilityOverrides` は「その日だけ」の設定。`isAvailable: false` で休業、
  `true` + 時刻で受付時間の差し替え。**曜日別設定を完全に置き換える**（マージしない）。

### 3.2 空き枠計算

`AvailabilityCalculator` が担う。手順:

1. 指定期間を予約メニューのタイムゾーンで日ごとに分割する
2. 曜日別受付時間（`weekly_availability`）から `durationMinutes` 刻みの枠を生成する
   （受付時間に収まらない端の枠は作らない）
3. 特定日の休業・時間変更（`availability_overrides`）を反映する
4. 最短受付時間（`minimumNoticeMinutes`）と最大予約可能日（`bookingWindowDays`）で切り詰める。
   過去日も返さない
5. Google FreeBusy API から Busy 時間を取得する
6. 前後バッファを含めた占有区間（`[start - bufferBefore, end + bufferAfter)`）が
   Busy 区間と重なる枠を除外する
7. DB 上の有効な予約（`confirmed` と期限内の `pending`）と重なる枠を除外する
8. 開始時刻順に返す

補足:

- **枠が 0 件の日も `slots: []` で返す。** カレンダー UI が「予約できない日」を描画できるようにするため。
- **1 リクエストの上限は 62 日**（`AvailabilityCalculator::MAX_RANGE_DAYS`）。超えると 400 `INVALID_RANGE`。
- **空き判定には予約の登録先カレンダーも含める。** Google 側で直接入れた予定や、
  他メニュー経由の予約で枠が二重に埋まらないようにするため。
- **Busy 時間が取得できない場合は枠を返さない**（502 `CALENDAR_ERROR`）。
  取得失敗を「空いている」と解釈すると、埋まっている時間を予約可能として見せてしまう。
- 時刻は DB では UTC（`timestamptz`）で保存し、API では予約メニューのタイムゾーンの
  オフセット付き RFC 3339（`2026-08-03T10:00:00+09:00`）で返す。

### 3.3 予約確定処理と二重予約の防止

空き枠を表示してから予約が来るまでに Google カレンダーへ別の予定が入る可能性があるため、
**表示時の計算結果は信用せず、予約 POST 時に必ず再計算する。**

```
予約 POST
  ↓ 入力・Turnstile・Idempotency-Key の検証
DB へ pending 予約を作成して枠を仮確保（排他制約で同時リクエストを直列化）
  ↓
Google FreeBusy で直前確認（自分の仮確保は除外して判定）
  ↓ 空いている
Google Calendar へ予定を作成
  ↓
DB を confirmed へ更新 → 確認メール送信
```

**DB の排他制約**が同時実行制御の本体。アプリのロックではなく DB に任せる。

```sql
CREATE EXTENSION IF NOT EXISTS btree_gist;

ALTER TABLE reservations
ADD CONSTRAINT reservations_active_overlap_exclude
EXCLUDE USING gist (
  booking_type_id WITH =,
  tstzrange(start_at, end_at, '[)') WITH &&
)
WHERE (status IN ('pending', 'confirmed'));
```

- 範囲は `[)`（終了時刻＝次の開始時刻は重なりとみなさない）。
- **`confirmed` も対象に含める。** Google カレンダーを空き**判定**の正本とするが、
  Google 側の反映が遅れて FreeBusy に直前の自分の予約が現れない窓が残るため、DB でも確定枠を押さえる。
- `pending` は仮確保。`expires_at`（5 分）を過ぎたものは無効として扱い、予約作成時に掃除する
  （排他制約は `expires_at` を見られないため）。`rake reservations:sweep_expired_pending` でも掃除できる。
- `cancelled` / `failed` は対象外なので、キャンセル・失敗した枠は自動的に解放される。

失敗時の振る舞い:

| 状況 | 結果 |
| --- | --- |
| 排他制約に当たった（同じ枠の先着あり） | 409 `SLOT_UNAVAILABLE`・仮確保は残らない |
| 直前確認で埋まっていた | 409 `SLOT_UNAVAILABLE`・仮確保を削除 |
| Google 予定の作成に失敗 | 502 `CALENDAR_ERROR`・予約を `failed` にして枠を解放・管理者へエラー通知 |
| 同じ Idempotency-Key の再送 | 先着の予約をそのまま返す（処理中なら 409 `REQUEST_IN_PROGRESS`） |

**Idempotency-Key は必須。** 同じキーの同時リクエストは「二重予約」ではなく「再送」として扱い、
枠の排他制約に先に当たった場合も `SLOT_UNAVAILABLE` にはせず冪等なリプレイに落とす。

日時変更（管理 API）も同じ順序を守る。まず DB の `start_at` / `end_at` を更新して枠を押さえ、
空き確認が通ったら新しい Google 予定を作り、最後に古い予定を削除する。
途中で失敗した場合はセーブポイントで元の日時へ戻す。

### 3.4 API 設計

すべての時刻は RFC 3339。リクエスト・レスポンスのキーは **camelCase**（外部サイトの JS から使うため）。
リクエストボディはネストを最小にしたフラット構造。仕様は `/openapi.json` と `/docs`（Swagger UI）。

#### 公開 API — 予約サイトのブラウザから呼ぶ。秘密の API キーは使わない

```
GET  /v1/public/booking-types/:slug
GET  /v1/public/booking-types/:slug/availability?from=&to=
POST /v1/public/booking-types/:slug/reservations
GET  /v1/public/reservations/:publicToken
POST /v1/public/reservations/:publicToken/cancel
```

保護は Origin 検証・IP 単位のレートリミット・Turnstile・入力検証・Idempotency-Key の併用（§5.2）。

予約 POST のボディ:

```json
{
  "startAt": "2026-08-03T10:00:00+09:00",
  "guest": {
    "name": "山田太郎",
    "email": "taro@example.com",
    "company": "株式会社サンプル",
    "phone": "090-0000-0000"
  },
  "answers": { "相談内容": "日報業務を自動化したい" },
  "turnstileToken": "..."
}
```

- `answers` は予約メニューごとに項目が変わるためスキーマを固定しない。
  文字列のマップとして保存し、キー数（最大 30）と値の長さ（最大 2000 文字）だけを検証する。
- `startAt` は空き枠 API が返した値をそのまま送る。枠の境界に一致しない時刻は受け付けない。

成功（201）:

```json
{
  "reservationId": "res_xxx",
  "status": "confirmed",
  "startAt": "2026-08-03T10:00:00+09:00",
  "endAt": "2026-08-03T11:00:00+09:00",
  "cancelUrl": "https://booking-api.genba-tsunagu.jp/c/res_xxx/<token>"
}
```

#### 管理 API — `X-Admin-Key` ヘッダで認証（利用者は自分だけ）

```
GET    /v1/admin/booking-types
POST   /v1/admin/booking-types
GET    /v1/admin/booking-types/:id
PATCH  /v1/admin/booking-types/:id
DELETE /v1/admin/booking-types/:id
GET    /v1/admin/reservations?status=&slug=&from=&to=&limit=&offset=
GET    /v1/admin/reservations/:id
POST   /v1/admin/reservations/:id/cancel
POST   /v1/admin/reservations/:id/reschedule
```

`PATCH` は送られたキーだけを更新する。ネストしたコレクション（`allowedOrigins` /
`weeklyAvailability` / `availabilityOverrides`）はキーがあれば**全置換**する
（部分更新は表現が曖昧でミスを招きやすい）。

初期設定は curl / API クライアントから行う。管理画面は必要になってから作る（§13）。

#### 運用 API

```
GET /health        liveness（DB を触らない）
GET /ready         readiness（DB 接続まで確認）
GET /openapi.json  OpenAPI 3.1 ドキュメント
GET /docs          Swagger UI
```

`/health` で DB を触らないのは、DB の一時障害でコンテナが再起動ループに入るのを避けるため。

### 3.5 メール通知

| 宛先 | 種類 |
| --- | --- |
| 予約者 | 予約確定 / キャンセル完了 / 日時変更 |
| 管理者 | 新規予約 / キャンセル / Google カレンダー連携エラー |

- 送信元は `SMTP_FROM`（既定 `info@genba-tsunagu.jp`）。
- **メール送信の失敗を理由に予約自体は失敗させない。** 予約確定後に送信し、エラーはログに記録する。
- 日時は予約メニューのタイムゾーンで「2026年8月3日(月) 10:00〜11:00」の形式。
- 予約確定メールにはキャンセル URL（生トークン）を載せる。トークンが手元にない場面
  （DB から読み直した予約）では URL を書かない。
- `ADMIN_NOTIFICATION_EMAIL` が未設定なら管理者メールは送らない（例外にはしない）。

### 3.6 エラー応答

形式は全エンドポイントで共通。

```json
{ "code": "SLOT_UNAVAILABLE", "message": "選択された時間は利用できなくなりました。", "details": ["..."] }
```

| code | HTTP | 意味 |
| --- | --- | --- |
| `BAD_REQUEST` | 400 | 必須パラメータ不足など |
| `INVALID_RANGE` | 400 | 期間指定が不正（逆順・62 日超） |
| `UNAUTHORIZED` | 401 | `X-Admin-Key` が不正 |
| `FORBIDDEN_ORIGIN` | 403 | 許可されていない Origin |
| `TURNSTILE_FAILED` | 403 | Bot 判定に失敗 |
| `NOT_FOUND` | 404 | 予約メニュー・予約が見つからない（トークン不正を含む） |
| `SLOT_UNAVAILABLE` | 409 | 枠が埋まっている |
| `REQUEST_IN_PROGRESS` | 409 | 同じ Idempotency-Key の処理中 |
| `NOT_CANCELLABLE` / `NOT_RESCHEDULABLE` | 409 | その状態では操作できない |
| `VALIDATION_FAILED` | 422 | 入力不正（`details` に詳細） |
| `INVALID_START_AT` | 422 | `startAt` の形式が不正 |
| `RATE_LIMITED` | 429 | レートリミット超過（`Retry-After` 付き） |
| `CALENDAR_ERROR` | 502 | Google カレンダー連携の失敗 |
| `CONFIGURATION_ERROR` | 503 | サーバー設定が不足（例: `ADMIN_API_KEY` 未設定） |

## 4. ドメインモデル・データモデル

```
BookingType 1 ─── * BookingTypeOrigin      許可 Origin
            1 ─── * WeeklyAvailability     曜日別受付時間
            1 ─── * AvailabilityOverride   特定日の受付変更
            1 ─── * Reservation            予約
```

| テーブル | 主な列 |
| --- | --- |
| `booking_types` | `name` / `slug`(uniq) / `description` / `duration_minutes` / `time_zone` / `minimum_notice_minutes` / `booking_window_days` / `buffer_before_minutes` / `buffer_after_minutes` / `google_booking_calendar_id` / `status` |
| `booking_type_origins` | `booking_type_id` / `origin`（`booking_type_id` とで uniq） |
| `weekly_availabilities` | `booking_type_id` / `day_of_week`(0=日〜6=土) / `start_time` / `end_time` |
| `availability_overrides` | `booking_type_id` / `date`（`booking_type_id` とで uniq） / `is_available` / `start_time` / `end_time` |
| `reservations` | `public_id`(uniq) / `booking_type_id` / `google_event_id` / `start_at` / `end_at` / `guest_name` / `guest_email` / `guest_company` / `guest_phone` / `answers`(jsonb) / `status` / `cancel_token_hash`(uniq) / `idempotency_key` / `expires_at` / `cancelled_at` |

- `reservations.status`: `pending` → `confirmed` → `cancelled`、または `pending` → `failed`。
- `google_booking_calendar_id` は予約メニュー単位の上書き。未指定なら `GOOGLE_BOOKING_CALENDAR_ID`。
- `idempotency_key` は `(booking_type_id, idempotency_key)` で部分一意インデックス（NOT NULL のみ）。
- `answers` の列名は草案の `answers_json` から `answers` に変えた（jsonb 型なので接尾辞が冗長）。
- `start_time` / `end_time` は `time` 型で、**予約メニューのタイムゾーンにおける壁時計時刻**として扱う
  （`WallClockTime` concern。§2.3 の制約を参照）。

## 5. 認証・認可

### 5.1 管理 API

- `X-Admin-Key` ヘッダの共有シークレット 1 本。比較は `ActiveSupport::SecurityUtils.secure_compare`。
- キーが未設定または 32 文字未満なら **503 を返す**。「未設定なら無認証で通る」状態を作らない。
- キーは Coolify の環境変数に置く。リポジトリ・OpenAPI ドキュメントには値を書かない。

### 5.2 公開 API とサイト側の責務

公開 API は無認証で開く（サイト側に秘密を置けないため）。代わりに次を併用する。

| 手段 | 何を防ぐか |
| --- | --- |
| 予約メニューごとの許可 Origin 検証 | ブラウザからの意図しないサイト経由の利用 |
| IP 単位のレートリミット | 総当たり・大量投稿 |
| Cloudflare Turnstile（予約 POST） | Bot による自動予約 |
| 入力検証（型・長さ・件数） | パラメータ汚染・巨大 JSON |
| Idempotency-Key | 再送による二重予約 |

**CORS はセキュリティ対策として数えない。** HTTP クライアントは Origin を偽装できるため、
ブラウザからの誤用を防ぐ最初の関門にすぎない。実質的な防御は上記の併用で行う。
`Origin` ヘッダがないリクエスト（サーバー間・curl）は許可し、Turnstile とレートリミットで守る。

予約の照会・キャンセルは、確認メールに載せた**生トークン**（`cancel_token`）で認可する。
DB にはその SHA-256 ハッシュだけを保存し、`public_id` を知っただけでは他人の予約を触れない。

**サイト側に置く設定はこれだけ。** Google の認証情報や管理 API キーは置かない。

```
NEXT_PUBLIC_BOOKING_API_URL=https://booking-api.genba-tsunagu.jp
NEXT_PUBLIC_BOOKING_TYPE=genba-tsunagu-consultation
NEXT_PUBLIC_TURNSTILE_SITE_KEY=
```

## 6. 外部連携

### 6.1 Google Calendar（サービスアカウント）

利用者が自分だけなので、一般ユーザー向けの Google OAuth は実装しない。
Google Cloud のサービスアカウントを使い、カレンダーを 2 種類に分ける。

| 用途 | 共有権限 | 環境変数 |
| --- | --- | --- |
| 空き判定対象（メインカレンダー等） | **予定の時間枠のみ表示** | `GOOGLE_BUSY_CALENDAR_IDS`（カンマ区切り） |
| 予約登録先（無料相談予約など） | 予定の変更権限 | `GOOGLE_BOOKING_CALENDAR_ID` |

これにより、個人予定のタイトル・内容を API サーバーへ渡さずに「予定が入っている時間」だけを
空き判定に使える。空き判定には **FreeBusy API のみ**を使い、予定の件名・説明・参加者は取得しない。

参加者（attendees）は予定に追加しない。ドメイン全体の委任がないサービスアカウントでは招待を送れず、
確認メールは自前の SMTP で送るため必要がない。

### 6.2 Google 予定の内容

件名:

```
【無料相談】株式会社サンプル / 山田太郎
```

説明:

```
予約ID: res_xxx
会社名: 株式会社サンプル
氏名: 山田太郎
メール: taro@example.com
電話番号: 090-0000-0000

相談内容:
日報業務を自動化したい
```

`extendedProperties.private.slotRelayReservationId` に `public_id` も保存する（後から突き合わせるため）。

### 6.3 Cloudflare Turnstile / SMTP

- Turnstile: `TURNSTILE_SECRET_KEY` 未設定なら検証をスキップする（ローカル開発向け）。
  本番で未設定なら起動時に警告を出す。Cloudflare 側の障害時は **fail closed**（弾く）。
- SMTP: `SMTP_HOST` 未設定なら送信しない。タイムアウトは 5 秒。

## 7. 課金・決済

MVP 対象外。決済は行わない。

## 8. 安全性・コンテンツポリシー

MVP 対象外。ユーザー投稿コンテンツを公開する機能はない
（`answers` は管理者と予約者本人しか読めない）。

## 9. プライバシー・データ取り扱い

- 保持する個人情報は予約者の氏名・メール・会社名・電話番号・`answers` のみ。
- **通常ログに個人情報を出さない。** `config.filter_parameters` で
  `guest` / `name` / `email` / `company` / `phone` / `answers` / `turnstileToken` を除外する。
- **Google サービスアカウントの秘密鍵をログへ出さない。** `private_key` もフィルタ対象。
  Google API のエラーは Google 由来のメッセージだけをログに残す。
- キャンセルトークンは SHA-256 ハッシュで保存する。生の値は発行時のメモリ上とメール本文のみ。
- 予約者の個人情報は公開 API では**トークンを持っている本人にだけ**返す。
- Google カレンダーの予定の件名・説明・参加者は公開 API へ一切返さない（FreeBusy しか取得しない）。
- 削除導線: 予約メニューを消すと紐づく設定は連鎖削除される。予約がある場合は削除を拒否する。

## 10. 運用・監視

- ヘルスチェック: Coolify から `/health`。DB まで確認したいときは `/ready`。
- ログは STDOUT（`log_tags: [:request_id]`）。`/health` はログを抑制する。
- バージョンは `/health` の `version` で確認できる（`APP_VERSION` または最上位 `VERSION` ファイル）。
- 定期実行（任意）: `rake reservations:sweep_expired_pending` — 期限切れの仮確保を掃除する。
- 状態確認: `rake reservations:stats` — 予約の状態別件数。
- バックアップ: Coolify の PostgreSQL バックアップを日次で取得し、保持期間を設定する。

## 11. 受け入れ条件

| 条件 | 状況 |
| --- | --- |
| 管理 API から予約メニューを登録できる | 実装済み・テスト有 |
| サイトから空き枠を取得できる | 実装済み・テスト有 |
| 60 分単位の予約枠が返る | 実装済み・テスト有 |
| Google カレンダーに予定がある枠は返らない | 実装済み・テスト有 |
| 予約 POST 直前に空き時間を再確認する | 実装済み・テスト有 |
| 同じ時間への同時予約を防止できる | 実装済み・テスト有（実スレッドで検証） |
| 予約後に Google カレンダーへ予定が作成される | 実装済み・テスト有 |
| 予約者と管理者へメールが送信される | 実装済み・テスト有 |
| キャンセル時に Google 予定も削除される | 実装済み・テスト有 |
| 管理 API は外部から無認証で操作できない | 実装済み・テスト有（全エンドポイント） |
| Google 予定の内容が公開 API へ漏れない | 実装済み・テスト有 |
| Swagger 上で API 仕様を確認できる | 実装済み・テスト有 |
| Coolify 上で API のヘルスチェックが成功する | **未確認**（デプロイ後に確認） |
| PostgreSQL のバックアップが取得される | **未設定**（Coolify 側で設定する） |

自動テストでの担保箇所は `docs/CODE_READING.md` を参照。

## 12. MVP 対象外

管理画面 / 一般ユーザー登録 / SaaS 課金 / Google OAuth / 複数ユーザー・組織 /
Outlook Calendar / LINE・Slack・SMS 通知 / 決済 / チーム担当者振り分け・ラウンドロビン /
Google Calendar Webhook / 複数タイムゾーンをまたぐチーム予約。

## 13. 将来の拡張方針

外部ユーザーへ提供する場合は、**現在の公開 API を維持したまま**次を追加する。

- ユーザー・組織 / Google OAuth / API キー発行 / 使用量制限 / Webhook / 管理画面 / 料金プラン

初版で SaaS 機能を先回りして実装しない。ただし、URL にバージョン `/v1` を含め、
予約メニューを `slug` で分離し、外部サイトから使える API 契約は最初から維持する。
WEB 画面が本格的に必要になった時点で `web/` を本番構成へ格上げする。

## 14. 未決事項

- staging 環境を用意するか（現状 local → production の 2 段構え）— unknown
- 複数インスタンスに増やす場合のレートリミット共有先（Redis を足すか）— unknown
- 予約フォームの項目定義（`answers` のスキーマ）を予約メニュー側に持たせるか — unknown
- キャンセル期限（何時間前まで許可するか）— 現状は制限なし。運用しながら判断する
