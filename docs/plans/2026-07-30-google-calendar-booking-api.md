# 2026-07-30 — Google カレンダー連携 予約 API（slot-relay MVP）

## やりたいこと

自分専用の予約 API サーバーを Coolify 上に構築する。予約画面は API 側では持たず、
`genba-tsunagu.jp` などの各 WEB サイトが独自デザインの画面を持ち、この API を呼ぶ。

```
genba-tsunagu.jp の予約フォーム
        ↓ API
予約 API サーバー（slot-relay）
        ↓
Google Calendar
```

API サーバーの責務は次の 4 点に限定する。

1. 予約可能時間の管理
2. Google カレンダーを考慮した空き枠の計算
3. 二重予約を防止した予約登録
4. Google カレンダーへの予定作成

## 背景・なぜ

- 予約フォームを各サイトに都度実装すると、空き枠計算と二重予約防止という
  一番壊れやすいロジックがサイトごとに重複する。ここだけを API として切り出す。
- 画面は各サイトのデザイン・ドメインに強く依存する。API 側で共通 UI を作ると
  かえって制約になるため、**画面は API の責務から外す**。
- 利用者は当面自分 1 人・Google アカウント 1 つなので、一般ユーザー向けの
  Google OAuth は実装せず**サービスアカウント**を使う。SaaS 機能は先回りしない。
- ただし将来の外部提供に備え、URL に `/v1` を含め、予約メニューを `slug` で分離し、
  「外部サイトから使える API 契約」だけは最初から維持する。

## 技術選定

| 項目 | 採用 | 理由 |
| --- | --- | --- |
| API | **Ruby on Rails 8.1（API モード）** | ユーザー指定。ActiveRecord から PostgreSQL の排他制約を直接扱える |
| DB | PostgreSQL 16 + `btree_gist` | `EXCLUDE USING gist` による二重予約防止が本質的に必要 |
| 参照実装 UI | **Next.js 15（App Router）** | ユーザー指定。サイト側実装の参照になる予約フォームを同居させる |
| Google 認証 | サービスアカウント | 利用者が自分だけ。OAuth 同意画面が不要 |
| Bot 対策 | Cloudflare Turnstile | 公開 POST を無認証で開けるため必須 |
| メール | ActionMailer + SMTP | 追加インフラなしで送れる |
| API 仕様 | OpenAPI 3.1 手書き + Swagger UI | gem を増やさず、レスポンス実体と 1 対 1 で管理する |
| ホスティング | Coolify | 既存運用に合わせる |

### 草案（Fastify / TypeScript）からの変更点

元の草案は Node.js + Fastify + Drizzle だったが、指定に合わせて **Rails** に置き換えた。
設計そのもの（責務分離・API 契約・データモデル・二重予約防止の方式）は草案どおりで、
実装技術のみ差し替えている。Zod → Rails のモデル検証＋コントローラでの型固定、
Drizzle → ActiveRecord マイグレーション、Fastify のレートリミットプラグイン → `rack-attack`。

CORS は当初 `rack-cors` を入れたが外した。許可 Origin を**予約メニュー単位**で DB 管理するため、
静的な設定では表現できず、動的な `origins` ブロックから autoload されるモデルを触ることになる
（初期化順・リロードの制約に触れる）。本リクエストの Origin 検証はどうせアプリ側で必要なので、
`PublicApi` concern に寄せて 1 か所にまとめた。プリフライトだけは `OriginAllowList`
（全メニューの Origin 集合・30 秒キャッシュ）で判定する。

### リポジトリ構成

草案では「初版は API だけなのでモノレポにしない」としていたが、技術指定に Next.js が
入ったため、最初から `api/` + `web/` の 2 ディレクトリ構成にした。`web/` は本番の
予約画面ではなく、**サイト側実装の参照実装（reference implementation）**であり、
公開 API だけで予約フォームが成立することを示す・E2E で導線を検証する役割を持つ。

```
slot-relay/
├── api/    Rails 8.1 API（本体）
├── web/    Next.js 予約フォーム参照実装
└── docs/
```

## 方針

### 空き枠計算

1. 指定期間を予約メニューのタイムゾーンで日ごとに分割
2. 曜日別受付時間から `durationMinutes` 刻みの枠を生成
3. 特定日の休業・時間変更（`availability_overrides`）を反映
4. 最短受付時間（`minimum_notice_minutes`）と最大予約可能日（`booking_window_days`）を反映
5. Google FreeBusy API から Busy 時間を取得
6. 前後バッファを含めて重複する枠を除外
7. DB 上の有効な予約（`confirmed` と期限内の `pending`）と重なる枠を除外
8. 開始時刻順に返す

時刻は DB では UTC（`timestamptz`）で保存し、API では RFC 3339 で返す。

### 二重予約防止

空き枠を表示した後に Google カレンダーへ別予定が入る可能性があるため、予約 POST 時に再確認する。

```
予約 POST
  ↓ 入力・Turnstile・Idempotency-Key 検証
DB へ pending 予約を作成して仮確保（排他制約で同時リクエストを直列化）
  ↓
Google FreeBusy で直前確認
  ↓ 空いている
Google Calendar へ予定作成
  ↓
DB を confirmed へ更新 → 確認メール送信
```

- `EXCLUDE USING gist` を `status IN ('pending','confirmed')` の部分インデックスで張る。
  草案では `status = 'pending'` のみだったが、**`confirmed` も含めた**。
  理由: Google カレンダーを正本にすると、Google 側の伝播遅延で FreeBusy に
  直前の自分の予約が現れず二重予約が通る窓が残る。DB 側でも確定枠を押さえる方が安全で、
  Google を正本とする判断（Google 側の予定を空き判定に使う）とは両立する。
- Google 予定の作成に失敗した場合は予約を `failed` にし、仮確保を解除する。
- メール送信失敗では予約を失敗させない（確定後に送信し、エラーはログに記録）。

### セキュリティ

公開 API は無認証で開くため、CORS だけを防御にしない（HTTP クライアントは Origin を偽装できる）。
Origin 検証・レートリミット・Turnstile・入力検証・Idempotency-Key を併用する。
詳細は `docs/SECURITY.md` に一次情報を置く。

## MVP 対象 / 対象外

**対象**: 予約メニュー登録 API / 曜日別受付時間 / 特定日の休業設定 / 空き枠取得 API /
予約登録 API / Google カレンダー予定作成 / 二重予約防止 / 予約確認メール / 管理者通知メール /
キャンセル API / OpenAPI・Swagger / Turnstile / Coolify デプロイ / PostgreSQL バックアップ

**対象外**: 管理画面 / 一般ユーザー登録 / SaaS 課金 / Google OAuth / 複数ユーザー・組織 /
Outlook Calendar / LINE・Slack・SMS 通知 / 決済 / 担当者振り分け・ラウンドロビン /
Google Calendar Webhook / 複数タイムゾーンをまたぐチーム予約

## 経緯・メモ

- **排他制約の範囲を広げた**（`pending` のみ → `pending` + `confirmed`）。上記の理由による。
  「Google を正本とする」方針は空き**判定**の話であり、同時実行制御は DB で行う。
- **`google_booking_calendar_id` を予約メニュー単位で持たせた**。草案の環境変数
  `GOOGLE_BOOKING_CALENDAR_ID` は既定値として残し、メニュー側で上書きできるようにした。
  サイトごとに登録先カレンダーを分けたくなる可能性が高いため。
- **キャンセルトークンは URL に生の値を載せ、DB にはハッシュのみ保存**する。
  `public_id` とは別のシークレットにし、`public_id` を知っただけではキャンセルできないようにした。
- **`answers` は JSONB で受ける**。予約メニューごとに質問項目が変わるため、
  MVP ではスキーマを固定せずキー・値の文字列マップとして保存する（サイズ上限のみ検証）。
- Turnstile はテスト環境と、シークレット未設定時は検証をスキップする。
  本番で未設定なら起動時に警告を出す（`config/initializers/slot_relay.rb`）。
- **タイムゾーン**は予約メニュー単位（`time_zone`）。Rails 側の `Time.zone` は UTC 固定にし、
  枠生成のときだけメニューのゾーンへ切り替える。取り違えを防ぐため
  `AvailabilityCalculator` の中だけで `Time.use_zone` を使う。
- `answers_json` → **`answers`** に列名を変更（jsonb 型なので `_json` 接尾辞が冗長）。

## 実装中に見つけたこと（Rails / PostgreSQL 固有）

作業中に踏んだ落とし穴。どれも「一度踏むと原因が分かりにくい」類なので記録しておく。

1. **`tstzrange` の排他制約は `timestamptz` カラムでないと作れない。**
   Rails の `t.datetime` は既定で `timestamp without time zone` を作る。そこに
   `tstzrange(start_at, end_at, '[)')` の GiST インデックスを張ろうとすると
   `functions in index expression must be marked IMMUTABLE` で失敗する
   （`timestamp → timestamptz` の暗黙キャストが `TimeZone` 設定に依存＝`STABLE` のため）。
   → `config/initializers/timestamptz.rb` で `datetime_type = :timestamptz` にした。
   なお `config.active_record.datetime_type` ではなく PostgreSQL アダプタのクラス属性なので、
   `ActiveSupport.on_load(:active_record_postgresqladapter)` の中で設定する必要がある。

2. **`time` カラムがタイムゾーン変換されると受付時間が丸ごと壊れる。**
   `time_zone_aware_types` に `:time` が含まれていると、`Time.zone` が `Asia/Tokyo` のときに
   保存した `10:00` が `19:00` として読み出される。空き枠計算は `Time.use_zone(メニューのTZ)` の
   中で受付時間を読むため、**枠が 1 つも生成されない**という形で表面化した。
   → `config.active_record.time_zone_aware_types = [:datetime]` を明示。
   受付時間は「壁時計時刻」であることを `WallClockTime` concern に閉じ込め、
   `Time.zone` に依存しないことを回帰テスト（`wall_clock_time_test.rb`）で固定した。

3. **ネストしたトランザクションで `ActiveRecord::Rollback` は無視される。**
   `requires_new: true` を付けないと親トランザクションに相乗りし、日時変更の失敗時に
   「元の日時へ戻す」つもりの `reload` が更新後の行を読み直すだけになっていた
   （テストではトランザクショナルテストが親トランザクションになるため必ず再現する）。
   → `Reservations::Rescheduler#move_slot` と `Reservations::Creator#hold_slot` を
   `transaction(requires_new: true)` に変更。

4. **同じ Idempotency-Key の同時リクエストは、キーの一意制約より先に枠の排他制約に当たる。**
   その結果、正しくは「冪等な再送」であるものが `SLOT_UNAVAILABLE` になっていた
   （同時実行テストで発覚）。→ `PG::ExclusionViolation` を捕まえた時点で
   Idempotency-Key を引き直し、既存の予約があればリプレイに落とすようにした。

5. **Rack 3.2 では `:unprocessable_entity` シンボルが引けない**（`:unprocessable_content` に改名）。
   バージョンによる揺れを避けるため、エラーコード → ステータスの対応表は数値で持つことにした。

6. **`config/master.key` を配布しないなら `SECRET_KEY_BASE` が必須。**
   `master.key` は当然 Git に入れないので Docker イメージにも入らない。その状態で
   production を起動すると `secret_key_base` を解決できずに落ちる。
   秘密は環境変数に一本化する方針なので、`credentials.yml.enc` と `master.key` は
   リポジトリから削除し、`SECRET_KEY_BASE` を必須の環境変数として文書化した
   （実際に `master.key` を退避して production 起動が落ちること・`SECRET_KEY_BASE` があれば
   起動することを確認済み）。

## レビュー指摘への対応（PR #2）

Codex の自動レビューで 3 件の指摘を受けた。いずれも実在の不具合だったので直した。

### 1. 排他制約のスコープが狭かった（P1・二重予約の穴）

**指摘**: 排他制約と空き判定を `booking_type_id` でスコープしていたため、
**同じ登録先カレンダーを共有する別の予約メニュー**同士では直列化されない。
どちらの `pending` も互いに衝突せず、Google 予定の作成前なので FreeBusy も両方「空き」と答え、
同じカレンダーの同じ時刻に 2 件の予定ができる。

**これは実在した。** しかも `google_booking_calendar_id` は未指定なら
`GOOGLE_BOOKING_CALENDAR_ID` にフォールバックする設計なので、**既定では全メニューが
同じカレンダーを共有する**。MILESTONE 1.x の「予約メニューを 2 つ目追加する」を
やった瞬間に踏む穴だった。逐次実行なら FreeBusy が拾うので、同時実行時だけ空く窓
——まさに DB 制約が塞ぐべき範囲。

**対応**: `reservations.booking_calendar_id`（NOT NULL）を追加し、排他制約のスコープを
`booking_type_id` → `booking_calendar_id` に変更。カレンダー単位はメニュー単位を包含するので、
これ 1 つで両方カバーできる。`AvailabilityCalculator#reservation_busy` も
`Reservation.for_calendar(...)` でメニューをまたいで引くようにした。
値は**予約時点で固定**する（あとでメニューの登録先を変えても既存予約の直列化範囲が動かないように）。
未設定のまま作れないようモデルで検証する。

### 2. Turnstile 検証が Idempotency-Key の照会より先だった（P1）

**指摘**: Turnstile のトークンは単回使用。応答を取りこぼしたクライアントが同じキー・
同じトークンで再送すると、既存予約を返すべき場面で `TURNSTILE_FAILED` になり、
Idempotency-Key の目的（安全な再送）が達成できない。

**これも実在した。** 対応として `Creator#call` の順序を入れ替え、Idempotency-Key の照会を
Turnstile 検証より前に持ってきた。既存予約の再送は「新しい予約試行」ではないので
Bot 判定をやり直す必要はない。

副作用として、キーを知っていれば Turnstile なしで予約内容（氏名・メール等）を引ける。
キーは実質ベアラトークンなので、参照実装の `newIdempotencyKey()` を
`Math.random()` フォールバックから `crypto.getRandomValues` に変更し、
`docs/SECURITY.md` に「キーは暗号論的乱数で生成すること」を明記した。

### 3. サマータイムで枠の時刻がずれる（P2）

**指摘**: 深夜 0 時に経過分数を足して枠の開始時刻を作っていたため、DST のある地域では
設定した壁時計時刻にならない（春の切り替え日は 10:00 設定が 11:00 になる）。

`time_zone` は任意の IANA ゾーンを受け付ける仕様なので**これも実在した**（MVP の運用は
Asia/Tokyo なので実害は出ていない）。開始時刻を `tz.local(date, 時, 分)` で組み立てる形に変更。
終了時刻は「開始から所要時間ぶんの経過時間」なので加算のままでよい（60 分の面談は実時間で 60 分）。
America/Los_Angeles の春・秋の切り替え日で回帰テストを追加した。

### メモ: schema.rb が排他制約を持っている

Rails 8.1 の schema dumper は `t.exclusion_constraint` を出力する。逆に言うと、
空の DB に対する `db:migrate` は schema.rb をロードしてしまい、マイグレーションを
書き換えても反映されない。今回は `db/schema.rb` を消してから `db:migrate` し直した。

## 疎通確認（ローカルの実サーバー）

テストのほかに、実際に `bin/rails server` を起動して以下を確認した
（Google はサービスアカウント未設定なので `NullClient`）。

- `/health` `/ready` `/openapi.json` `/docs` — すべて 200
- 許可 Origin には `Access-Control-Allow-Origin` と `Vary: Origin` が付き、不許可 Origin は 403
- プリフライト（OPTIONS）は許可 Origin のみ 204、不許可は 403
- 予約 POST → 201・キャンセル URL つき。同じ枠に別キーで 409、同じキーで再送すると同じ予約が返る
- 生トークンでは照会できるが `public_id` では 404
- 管理 API は無認証で 401、`X-Admin-Key` ありで 200
- キャンセル・日時変更で枠が空きに戻る／受付時間外への変更は 409 で元の日時を保つ
- 予約 POST を連続で叩くとレートリミットが 429 を返す
- development ではメールを `tmp/mails` へ書き出し、日本語の件名・本文・
  キャンセル URL が正しいことを目視確認

## テスト

- api: 176 件（`bin/rails test`）— モデル・空き枠計算・予約処理・コントローラ・メーラー・
  ユースケース通し・同時実行。
- web: 15 件（`npm test`）— API クライアントと画面遷移。
- 二重予約は**実スレッド・別コネクション**で検証している。トランザクショナルテストを切らないと
  他スレッドからセットアップデータが見えないため、`DoubleBookingTest` だけ
  `use_transactional_tests = false` にして手動で掃除している。
- 外部 HTTP（Google / Turnstile）は WebMock で遮断し、Google クライアントは
  `SlotRelay.calendar_client` に fake を注入して差し替える。
- 同時実行テストの安定性は、フルスイートを 8 回連続で実行して確認した。
