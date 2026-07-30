# Changelog

このプロジェクトの特筆すべき変更はすべてこのファイルに記録する。

- フォーマットは [Keep a Changelog](https://keepachangelog.com/ja/1.1.0/) に準拠
- バージョニングは [Semantic Versioning](https://semver.org/lang/ja/) に従う
- バージョン番号・タグ・GitHub Release は GitHub Actions
  （`.github/workflows/version-bump.yml`）が `main` へのスカッシュマージごとに自動採番する
- 作業のたびに `Unreleased` セクションへ変更内容を追記すること（CLAUDE.md 参照）

## [Unreleased]

### Changed

- **本番 API のドメインを `booking-api.genba-tsunagu.jp` から
  `booking-api.stagehubs.net` に変更した。** 将来複数のサイトから使う想定のため、
  特定サイトのサブドメインには置かない。
  影響するのはドキュメントと既定値（`PUBLIC_BASE_URL` / `ALLOWED_HOSTS` /
  `NEXT_PUBLIC_BOOKING_API_URL` のフォールバック）のみで、動作するコードは変わらない。
  実値は Coolify の環境変数で指定する。
  **Google Cloud の「承認済みのリダイレクト URI」も新ドメインに差し替えること**
  （`https://booking-api.stagehubs.net/v1/admin/google/oauth/callback`）。
  利用側サイト（`genba-tsunagu.jp`）の許可 Origin・メール差出人・予約メニューの slug は変更なし。

## [0.3.1] - 2026-07-30

### Security

- **本番で `TURNSTILE_SECRET_KEY` が未設定なら予約 POST を 503 にした。**
  `TurnstileVerifier` は未設定だと素通しするため、設定漏れのまま公開すると
  予約 POST の防御がレートリミットだけになり、IP を変えればダミー予約で
  カレンダーを埋められた。管理 API キー未設定で 503 にするのと同じ考え方に揃えた。
  development / test は従来どおり未設定でも動く。
- **本番では `/docs` と `/openapi.json` を既定で 404 にした。**
  秘密情報は含まないが、管理 API のパス構成（とくに誰でも開ける
  `/v1/admin/google/setup`）を偵察させないため。403 ではなく 404 にして存在も伏せる。
  公開したいときは `ENABLE_API_DOCS=true`。Swagger UI に `noindex, nofollow` と
  `no-referrer` も付けた。
  経緯は `docs/plans/2026-07-30-harden-production-defaults.md`。

### Changed

- 起動時の設定チェックは従来どおり警告にとどめ、拒否は各エンドポイントで行う方針を維持した
  （起動を落とすと Google 連携の初回セットアップに到達できず、
  Coolify のヘルスチェックでロールバックループになるため）。

## [0.3.0] - 2026-07-30

### Changed

- 設定画面のセッション Cookie を `SameSite=Strict` から **`Lax`** に変えた。
  Strict だと Google からのコールバック（別サイト起点のナビゲーション）で Cookie が送られず、
  連携に成功しても必ずログイン画面へ戻ってしまう。Lax でもクロスサイトの POST には
  送られないため CSRF 対策は維持される（署名付き CSRF トークンも別途ある）。
- 認可コードの交換に失敗したとき、Google の応答本文（`error` / `error_description`）を
  ログに出すようにした。Signet の例外メッセージだけでは原因が分からなかったため。
- `CLAUDE.md` のブランチ運用に「PR 作成で止めず、CI 確認後にスカッシュマージして
  `main` を更新するところまで完了させる」を追加した。
- **Google カレンダー連携の認証をサービスアカウントからユーザー OAuth へ移行した**（破壊的変更）。
  経緯・却下した案は `docs/plans/2026-07-30-google-oauth-calendar-selection.md`。
  - **環境変数が変わる。** `GOOGLE_SERVICE_ACCOUNT_EMAIL` / `GOOGLE_SERVICE_ACCOUNT_PRIVATE_KEY`
    を廃止し、`GOOGLE_OAUTH_CLIENT_ID` / `GOOGLE_OAUTH_CLIENT_SECRET` /
    `GOOGLE_OAUTH_REDIRECT_URI`（省略可）を追加。デプロイ後に一度だけ連携操作が要る（`docs/DEPLOY.md`）。
  - スコープを全権の `calendar` から `calendar.calendarlist.readonly` /
    `calendar.freebusy` / `calendar.events` の 3 つに絞った。
  - refresh token は `SECRET_KEY_BASE` 由来の鍵で暗号化して DB に保存する。
    **`SECRET_KEY_BASE` を差し替えると再連携が必要**（`docs/SECURITY.md`）。
  - `GOOGLE_BUSY_CALENDAR_IDS` / `GOOGLE_BOOKING_CALENDAR_ID` は「予約メニュー側で
    未選択のときの既定値」に降格。カレンダーは画面から選ぶ。
- 未連携・トークン失効時の挙動を変えた。本番は `GoogleCalendar::UnavailableClient` が
  **502（CALENDAR_ERROR）** を返す。従来のように黙って「Busy 時間が空」＝全部空きにはしない。
  `NullClient` は development / test のみ。
- `config.api_only = true` のまま `ActionDispatch::Cookies` を戻した。
  Cookie を使うのは Google 連携の設定画面だけで、公開 API・管理 API は従来どおり Cookie を使わない。
- `db/seeds.rb` の許可 Origin を `DEV_ALLOWED_ORIGINS` で追加できるようにした。
  参照実装 UI のポートを 3000 以外にしても CORS で弾かれない。既定値は従来どおり。
- README の「ローカルで動かす」「テスト」を compose 前提の手順に差し替えた。

### Added

- **Google 連携とカレンダー選択の画面・API を追加した。**
  - `POST /v1/admin/google/oauth/url` — 同意画面の URL を発行（10 分で失効）。
    管理 API キーを URL に載せないため、発行と同意を 2 段に分けている。
  - `GET /v1/admin/google/oauth/callback` — 同意後の戻り先。Google からのリダイレクトで
    `X-Admin-Key` を付けられないため、署名付き `state` で正当性を確認する。
  - `GET /v1/admin/google/calendars` — 連携アカウントのカレンダー一覧（書き込み可否つき）。
  - `POST /v1/admin/google/login` / `POST /v1/admin/google/connect` —
    **ブラウザだけで連携を完結させる導線**。設定画面を直接開くとログインフォームが出て、
    管理 API キーを POST ボディで送ると短期セッションに引き換わる。
    そこから「Google と連携する」で同意画面へ進める（curl が要らない）。
  - `GET|POST /v1/admin/google/setup` — **カレンダー設定画面**（サーバー描画の HTML）。
    予約メニューごとに登録先カレンダー（ラジオ）と空き判定カレンダー（チェックボックス）を選ぶ。
    認証は同意直後の短期セッション Cookie（30 分・HttpOnly・SameSite=Strict）か `X-Admin-Key`。
    Cookie 認証の POST には署名付き CSRF トークンを必須にした。
  - `POST /v1/admin/google/disconnect` — 連携解除。
- **空き判定に使うカレンダーを予約メニュー単位で持てるようにした**
  （`booking_types.google_busy_calendar_ids`）。管理 API の `googleBusyCalendarIds` でも指定できる。
  未設定なら従来どおり `GOOGLE_BUSY_CALENDAR_IDS` を使う。
- `google_connections` テーブル（連携アカウント 1 件・refresh token は暗号化）。

- **ローカル開発環境を Docker Compose に載せた**（`compose.yaml` / `api/Dockerfile.dev` /
  `.env.example`）。`docker compose up -d` だけで API + PostgreSQL 16 + 参照実装 UI が起動する。
  ホストに Ruby・PostgreSQL を入れる必要がなくなった。
  経緯は `docs/plans/2026-07-30-local-compose.md`。
  - ポートは `.env` で変更でき、既定は API 3011 / web 3012 / PostgreSQL 55432
    （3000・3001 は他プロジェクトと衝突しやすいため既定をずらした）。
  - `GOOGLE_OAUTH_CLIENT_ID` / `_SECRET` / `_REDIRECT_URI` はルートの `.env` に書けば
    api コンテナへ渡る（compose のルート `.env` は本来 `${...}` の展開にしか使われないため、
    明示的に受け渡している）。`api/.env` に書いてもよい。
  - コンテナはホストと同じ uid/gid で動かし、バインドマウント先に root 所有のファイルを作らない。
  - DB データは名前付きボリューム `db-data`。`docker compose down -v` で明示的に削除する。

### Changed

- `db/seeds.rb` の許可 Origin を `DEV_ALLOWED_ORIGINS` で追加できるようにした。
  参照実装 UI のポートを 3000 以外にしても CORS で弾かれない。既定値は従来どおり。
- README の「ローカルで動かす」「テスト」を compose 前提の手順に差し替えた。

## [0.2.0] - 2026-07-30

### Added

- **Google カレンダー連携の予約 API（`api/`）を新設**。Ruby on Rails 8.1（API モード）+ PostgreSQL 16。
  設計の一次情報は `docs/DESIGN.md`、経緯は `docs/plans/2026-07-30-google-calendar-booking-api.md`。
  - 予約メニュー（`booking_types`）・曜日別受付時間・特定日の休業／時間変更・許可 Origin のデータモデル。
  - 空き枠計算（`AvailabilityCalculator`）— 曜日別受付時間からの枠生成、特定日オーバーライド、
    最短受付時間、最大予約可能日、Google FreeBusy の Busy 時間、前後バッファ、既存予約の除外。
    枠が 0 件の日も `slots: []` で返す。Busy 時間を取得できない場合は 502 にして空き扱いにしない。
  - 予約確定（`Reservations::Creator`）— pending での仮確保 → Google FreeBusy での直前確認 →
    Google 予定作成 → confirmed へ更新 → メール送信。
  - **二重予約防止**を PostgreSQL の `EXCLUDE USING gist`（`btree_gist` + `tstzrange`）で実装。
    対象は `pending` と `confirmed`、スコープは**登録先 Google カレンダー単位**
    （予約メニュー単位だと、既定で同じカレンダーを共有する別メニューがすり抜ける）。
    実スレッド・別コネクションでの同時実行テストつき。
  - `Idempotency-Key` を必須化。同じキーの同時リクエストは冪等な再送として扱う。
  - 公開 API — 予約メニュー取得 / 空き枠取得 / 予約登録 / トークンによる照会・キャンセル。
  - 管理 API — 予約メニューの CRUD、予約の一覧・詳細・キャンセル・日時変更（`X-Admin-Key`）。
  - 運用 API — `/health`（DB を触らない liveness）/ `/ready`（DB 接続まで確認）。
  - メール（ActionMailer + SMTP）— 予約者向け確定・キャンセル・日時変更、管理者向け新規予約・
    キャンセル・カレンダー連携エラー。送信失敗では予約を失敗させずログに記録する。
  - OpenAPI 3.1 ドキュメント（手書き・`/openapi.json`）と Swagger UI（`/docs`）。
  - Cloudflare Turnstile 検証と rack-attack によるレートリミット（公開／予約 POST／管理で別枠）。
  - 本番用 Dockerfile（非 root 実行）、`bin/docker-entrypoint`、`.env.example`、
    `rake reservations:sweep_expired_pending` / `reservations:stats`。
- **予約フォームの参照実装（`web/`）を新設**。Next.js 15（App Router）+ React 19 + TypeScript。
  公開 API 2 本だけで予約画面が成立することを示すためのもので、本番デプロイ対象ではない。
  日付選択 → 時間選択 → 入力 → Turnstile → 予約 POST → 完了、およびキャンセル画面。
- **CI（`.github/workflows/ci.yml`）を追加**。api は `bundler-audit` + Rails テスト（PostgreSQL 16 の
  service コンテナ）、web は型チェック・テスト・ビルドを PR ごとに実行する。
- テストを 191 件追加（api 176 / web 15）。ユニット・ユースケース（登録 → 空き枠 → 予約 → 照会 →
  キャンセルの通し）・画面遷移・同時実行をカバー。担保箇所の一覧は `docs/CODE_READING.md`。

- `.gitattributes` を新設し、`docs/CHANGELOG.md merge=union` を指定。複数 PR が `Unreleased` に
  追記した際のマージコンフリクトを、Git 組み込みの union マージドライバ（両方の行を残して自動マージ）
  で仕組みとして解消。あわせて `CLAUDE.md` にルールとして明記。

- `docs/MILESTONE.md` を新設。ざっくりした目標（「1.0 で何をしたいか」等）を区切り自由で書くファイル。
- `docs/plans/`（＋ `docs/plans/README.md`）を新設。作業ごとの plan（やりたいこと・背景・方針・経緯）を
  1 ファイルとして残す運用の受け皿。従来の `DECISIONS.json`（「なぜ」の記録）を置き換える。
- `Template Init` ワークフロー（`.github/workflows/template-init.yml`）を追加。テンプレートから
  作成した初回 push で README をリポジトリ名だけの最小構成に書き換え、`VERSION` を `0.1.0` に
  リセットし、プレースホルダを置換して初期化コミットを積む（実行後に自身と `docs/TEMPLATE_GUIDE.md`
  ・初期化マーカーを削除）。
- 未初期化マーカー `.github/.template-init-pending` を追加。

### Changed

- `docs/DESIGN.md` / `docs/CODE_READING.md` / `docs/DEPLOY.md` / `docs/SECURITY.md` /
  `docs/MILESTONE.md` / `README.md` をテンプレートのひな形から実際の内容へ差し替え。
- `.gitignore` に Rails / Next.js のビルド成果物・依存ディレクトリを追加。
- 草案（Node.js + Fastify + Drizzle + Zod）から **Ruby on Rails + Next.js** へ技術選定を変更。
  設計（責務分離・API 契約・データモデル・二重予約防止の方式）は草案どおり。
- 草案からの設計変更 2 点（理由は plan に記載）:
  - 排他制約の対象を `pending` のみ → `pending` + `confirmed` に拡大。Google 側の反映遅延で
    FreeBusy に自分の直前予約が現れない窓を DB 側で塞ぐため。
  - `google_booking_calendar_id` を予約メニュー単位で上書きできるようにした（環境変数は既定値）。

- 記録の管理を Markdown 3 本（`docs/MILESTONE.md` / `docs/plans/` / `docs/CHANGELOG.md`）に一本化。
  それに伴い `CLAUDE.md` / `README.md` / `docs/TEMPLATE_GUIDE.md` / `docs/DESIGN.md` /
  `docs/CODE_READING.md` / `.github/pull_request_template.md` の記述を更新。
- `version-bump.yml` を、初期化マーカーが残っている間はバージョン bump しないようガード。
- テンプレートの VERSION ドリフト（テンプレ本体の bump 済みバージョンを引き継ぐ問題）とその
  リセット方針を `docs/TEMPLATE_GUIDE.md` / `README.md` に明記。

### Removed

- `PROJECT_STATUS.json` / `PROJECT_STATUS.schema.json` / `DECISIONS.json` / `DECISIONS.schema.json`
  を廃止（固定スキーマ JSON のメンテ負荷で開発が遅くなるため）。
- 上記 JSON を検証する `.github/workflows/schema-check.yml` を削除。
- `PROJECT_STATUS.json` / `DECISIONS.json` を読み取り報告する `.claude/skills/project-status/` を削除。

## [0.1.2] - 2026-07-11

### Added

- テンプレート利用ガイドを `docs/TEMPLATE_GUIDE.md` として分離（旧 README の内容）。

### Changed

- `README.md` を新規プロジェクト用のスケルトンに刷新（テンプレートから作成した repo が
  そのまま自分の README として使える形にし、セットアップ手順とプレースホルダ表を掲載）。

## [0.1.1] - 2026-07-11

### Added

- プロジェクトの初期セットアップ（boilerplate から生成）

### Changed

### Fixed
