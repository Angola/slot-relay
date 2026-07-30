# DEPLOY.md — デプロイ手順

> 各環境へのデプロイ方法・必要な環境変数・ロールバック手順をまとめる。
> 設計の一次情報は `docs/DESIGN.md`（§2.2 ホスティング、§10 運用・監視）。

## 環境一覧

| 環境 | 用途 | URL | デプロイ方法 |
| --- | --- | --- | --- |
| local | 開発 | api: `http://localhost:3001` / web: `http://localhost:3000` | 手動（下記） |
| staging | 用意しない（未決事項 DESIGN §14） | — | — |
| production | 本番 | `https://booking-api.genba-tsunagu.jp` | Coolify の自動デプロイ（`main` へのマージ） |

`web/`（Next.js）は予約フォームの**参照実装**であり、デプロイ対象ではない。
実際の予約画面は各サイト（genba-tsunagu.jp など）が自前で持ち、公開 API を呼ぶ。

## ローカル開発

```bash
# API
cd api
bin/setup                      # bundle install + DB 作成・マイグレーション
bin/rails db:seed              # 開発用の予約メニューを作る
bin/rails server -p 3001

# 参照実装 UI（別ターミナル）
cd web
npm install
cp .env.example .env.local      # NEXT_PUBLIC_BOOKING_API_URL=http://localhost:3001 に直す
npm run dev
```

Google サービスアカウントが未設定のときは `GoogleCalendar::NullClient` が使われ、
Busy 時間は空・予定は作成されない（起動時に警告が出る）。本番では未設定だと起動時に例外になる。

## 必要な環境変数

`api/.env.example` が一次情報。本番では **Coolify の環境変数**に設定する（リポジトリに値を書かない）。

| 変数名 | 用途 | 例 / 既定 |
| --- | --- | --- |
| `RAILS_ENV` | 実行環境 | `production` |
| `PORT` | 待ち受けポート | `3001` |
| `DATABASE_URL` | Coolify PostgreSQL の接続 URL | `postgres://...` |
| `SECRET_KEY_BASE` | **本番で必須。** `openssl rand -hex 64` で生成。Rails の暗号化 credentials は使わず、秘密はすべて環境変数に置くため（`config/master.key` をイメージに同梱しない） | — |
| `PUBLIC_BASE_URL` | 公開 URL（キャンセル URL・メールのリンク生成） | `https://booking-api.genba-tsunagu.jp` |
| `ALLOWED_HOSTS` | Host ヘッダ検証（カンマ区切り。未設定なら検証しない） | `booking-api.genba-tsunagu.jp` |
| `ADMIN_API_KEY` | 管理 API の共有シークレット。**32 文字以上**。未設定なら管理 API は 503 | `openssl rand -base64 48` で生成 |
| `GOOGLE_SERVICE_ACCOUNT_EMAIL` | サービスアカウントのメール | `slot-relay@....iam.gserviceaccount.com` |
| `GOOGLE_SERVICE_ACCOUNT_PRIVATE_KEY` | 秘密鍵（改行は `\n` のままでよい） | `-----BEGIN PRIVATE KEY-----\n...` |
| `GOOGLE_BUSY_CALENDAR_IDS` | 空き判定に使うカレンダー ID（カンマ区切り） | `me@example.com` |
| `GOOGLE_BOOKING_CALENDAR_ID` | 予約の登録先カレンダー ID | `xxxx@group.calendar.google.com` |
| `SMTP_HOST` / `SMTP_PORT` | SMTP サーバー（未設定なら送信しない） | `smtp.example.com` / `587` |
| `SMTP_USER` / `SMTP_PASSWORD` | SMTP 認証情報 | — |
| `SMTP_FROM` | 送信元 | `info@genba-tsunagu.jp` |
| `ADMIN_NOTIFICATION_EMAIL` | 管理者通知の宛先（未設定なら送らない） | `me@example.com` |
| `TURNSTILE_SECRET_KEY` | Cloudflare Turnstile（未設定なら検証をスキップ） | — |
| `CANCEL_URL_BASE` | キャンセル画面をサイト側に置く場合の URL ベース | `https://genba-tsunagu.jp/booking` |
| `RAILS_LOG_LEVEL` | ログレベル | `info` |
| `RAILS_MAX_THREADS` | Puma スレッド数・DB プール | `5` |
| `APP_VERSION` | `/health` が返すバージョン（ビルド時に注入） | `0.1.0` |
| `PUBLIC_RATE_LIMIT_PER_IP` / `_PERIOD` | 公開 API のレートリミット | `120` / `60` |
| `RESERVATION_RATE_LIMIT_PER_IP` / `_PERIOD` | 予約 POST・キャンセルのレートリミット | `5` / `600` |
| `ADMIN_RATE_LIMIT_PER_IP` / `_PERIOD` | 管理 API のレートリミット | `60` / `60` |

## 初回セットアップ

### 1. Google Cloud

1. プロジェクトを作り **Google Calendar API** を有効にする
2. サービスアカウントを作り、JSON キーを発行する
3. Google カレンダー側で 2 種類の共有を設定する（DESIGN §6.1）
   - **空き判定対象**（メインカレンダー等）→ サービスアカウントに「**予定の時間枠のみ表示**」
   - **予約登録先**（無料相談予約など専用カレンダー）→ サービスアカウントに「**予定の変更権限**」
4. それぞれのカレンダー ID を `GOOGLE_BUSY_CALENDAR_IDS` / `GOOGLE_BOOKING_CALENDAR_ID` に設定する

### 2. Cloudflare Turnstile

1. Turnstile のウィジェットを作成する（サイトは予約フォームを置くドメイン）
2. シークレットキーを `TURNSTILE_SECRET_KEY`（API 側）に設定する
3. サイトキーはサイト側の `NEXT_PUBLIC_TURNSTILE_SITE_KEY` に設定する

### 3. Coolify

**booking-postgres**（PostgreSQL）

- Coolify の PostgreSQL リソースを作る
- **外部公開はしない**（内部ネットワークのみ）
- 日次バックアップを有効にし、保持期間を設定する
- 生成された接続 URL を `booking-api` の `DATABASE_URL` に設定する

**booking-api**

| 設定 | 値 |
| --- | --- |
| Build Pack | Dockerfile |
| Base Directory | `/api` |
| Dockerfile Location | `/api/Dockerfile` |
| Domain | `https://booking-api.genba-tsunagu.jp` |
| Port（Ports Exposes） | `3001` |
| Health Check Path | `/health` |
| Auto Deploy | `main` ブランチ |

- 上記の環境変数をすべて設定する
- `btree_gist` 拡張はマイグレーションが `CREATE EXTENSION` で作る（作成権限のあるロールが必要）

### 4. 予約メニューの登録

管理 API から登録する（管理画面は MVP 対象外）。

```bash
curl -X POST https://booking-api.genba-tsunagu.jp/v1/admin/booking-types \
  -H "X-Admin-Key: $ADMIN_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "無料相談",
    "slug": "genba-tsunagu-consultation",
    "durationMinutes": 60,
    "timeZone": "Asia/Tokyo",
    "minimumNoticeMinutes": 1440,
    "bookingWindowDays": 30,
    "allowedOrigins": ["https://genba-tsunagu.jp"],
    "weeklyAvailability": [
      {"dayOfWeek": 1, "startTime": "10:00", "endTime": "18:00"},
      {"dayOfWeek": 2, "startTime": "10:00", "endTime": "18:00"},
      {"dayOfWeek": 3, "startTime": "10:00", "endTime": "18:00"},
      {"dayOfWeek": 4, "startTime": "10:00", "endTime": "18:00"},
      {"dayOfWeek": 5, "startTime": "10:00", "endTime": "18:00"}
    ]
  }'
```

### 5. サイト側（genba-tsunagu.jp）

サイト側に置く設定は 3 つだけ。Google の認証情報・管理 API キーは置かない。

```
NEXT_PUBLIC_BOOKING_API_URL=https://booking-api.genba-tsunagu.jp
NEXT_PUBLIC_BOOKING_TYPE=genba-tsunagu-consultation
NEXT_PUBLIC_TURNSTILE_SITE_KEY=...
```

実装は `web/`（`lib/bookingApi.ts` と `components/BookingForm.tsx`）をそのまま参考にできる。

## デプロイ手順

1. 作業ブランチから `main` へ PR を出し、**スカッシュマージ**する
2. `version-bump.yml` が `VERSION` を更新し、タグと GitHub Release を作る
3. Coolify の Auto Deploy が `main` を検知してビルド・デプロイする
4. マイグレーションは `bin/docker-entrypoint` が起動時に `db:prepare` で適用する
   （単一インスタンス運用を前提とした割り切り。インスタンスを増やすときは分離すること）
5. デプロイ後の確認
   ```bash
   curl -s https://booking-api.genba-tsunagu.jp/health   # {"status":"ok","version":"..."}
   curl -s https://booking-api.genba-tsunagu.jp/ready    # {"status":"ready","database":"ok"}
   ```
   `/docs` で Swagger UI が開けることも確認する

## ロールバック手順

1. Coolify のデプロイ履歴から直前のデプロイを選び **Rollback** する
2. マイグレーションを戻す必要がある場合は、先に DB を戻す
   ```bash
   # コンテナ内
   bin/rails db:rollback STEP=1
   ```
   列の削除を伴うマイグレーションは、ロールバックでデータが失われる。
   本番では「先にコードを戻し、DB はそのまま」で済む変更を優先する
3. 復旧できない場合は Coolify の PostgreSQL バックアップからリストアする

## 定期実行（任意）

期限切れの仮確保（`pending`）は予約作成時にも掃除されるが、予約が来ない期間に残り続けるのを防ぐため
1 日 1 回程度回してもよい。

```bash
bin/rails reservations:sweep_expired_pending
```

## リリースフロー

- `main` へのスカッシュマージで `version-bump.yml` が自動でバージョン採番・タグ付け・
  GitHub Release 作成を行う（bump レベルは PR タイトルの Conventional Commits で決まる）。
- production へのデプロイは Coolify の **自動デプロイ**。
- CI（`.github/workflows/ci.yml`）は PR ごとに api のテスト・依存監査と web の型チェック・
  テスト・ビルドを実行する。
