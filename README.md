# slot-relay

Google カレンダー連携の**予約 API サーバー**。予約画面は持たず、各 WEB サイトが自前のデザインで
画面を作り、この API を呼ぶ。

```
genba-tsunagu.jp の予約フォーム
        ↓ API
予約 API サーバー（slot-relay）
        ↓
Google Calendar
```

API の責務は 4 点だけ。

1. 予約可能時間の管理
2. Google カレンダーを考慮した空き枠の計算
3. 二重予約を防止した予約登録
4. Google カレンダーへの予定作成

## 構成

| ディレクトリ | 中身 |
| --- | --- |
| `api/` | 予約 API 本体（Ruby on Rails 8.1・API モード / PostgreSQL 16）。**これがプロダクト** |
| `web/` | 予約フォームの**参照実装**（Next.js 15）。デプロイ対象ではない |
| `docs/` | ドキュメント |

## ドキュメント

| ファイル | 内容 |
| --- | --- |
| [`docs/DESIGN.md`](docs/DESIGN.md) | プロダクト仕様・アーキテクチャ（**一次情報**） |
| [`docs/CODE_READING.md`](docs/CODE_READING.md) | どこから読めばいいか・テストの地図 |
| [`docs/DEPLOY.md`](docs/DEPLOY.md) | Coolify へのデプロイ手順・環境変数 |
| [`docs/SECURITY.md`](docs/SECURITY.md) | セキュリティ懸念事項と対策状況 |
| [`docs/MILESTONE.md`](docs/MILESTONE.md) | やりたいこと |
| [`docs/CHANGELOG.md`](docs/CHANGELOG.md) | 変更履歴 |
| [`docs/plans/`](docs/plans/) | 作業ごとの背景・方針・意思決定 |

開発ルールは [`CLAUDE.md`](CLAUDE.md)。

## ローカルで動かす

前提: Ruby 3.3 / Node.js 22 / PostgreSQL 16

```bash
# API（http://localhost:3001）
cd api
bin/setup                 # bundle install + DB 作成・マイグレーション
bin/rails db:seed         # 開発用の予約メニューを作る
bin/rails server -p 3001

# 参照実装 UI（http://localhost:3000）— 別ターミナル
cd web
npm install
cp .env.example .env.local   # NEXT_PUBLIC_BOOKING_API_URL=http://localhost:3001 に直す
npm run dev
```

Google サービスアカウント未設定でも動く（Busy 時間は空・予定は作成されない）。
API 仕様は http://localhost:3001/docs（Swagger UI）で確認できる。

## テスト

```bash
cd api && bin/rails test    # 165 件
cd web && npm test          # 15 件
```

## API の概要

公開 API（予約サイトのブラウザから呼ぶ。秘密の API キーは不要）

```
GET  /v1/public/booking-types/:slug
GET  /v1/public/booking-types/:slug/availability?from=&to=
POST /v1/public/booking-types/:slug/reservations     # Idempotency-Key 必須
GET  /v1/public/reservations/:publicToken
POST /v1/public/reservations/:publicToken/cancel
```

管理 API（`X-Admin-Key` 必須）

```
GET|POST           /v1/admin/booking-types
GET|PATCH|DELETE   /v1/admin/booking-types/:id
GET                /v1/admin/reservations
GET                /v1/admin/reservations/:id
POST               /v1/admin/reservations/:id/cancel
POST               /v1/admin/reservations/:id/reschedule
```

運用

```
GET /health  /ready  /openapi.json  /docs
```

詳細は [`docs/DESIGN.md §3.4`](docs/DESIGN.md) と `/docs`（Swagger UI）を参照。

## サイト側に置く設定

Google の認証情報や管理 API キーはサイト側に置かない。

```
NEXT_PUBLIC_BOOKING_API_URL=https://booking-api.genba-tsunagu.jp
NEXT_PUBLIC_BOOKING_TYPE=genba-tsunagu-consultation
NEXT_PUBLIC_TURNSTILE_SITE_KEY=
```
