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
| `compose.yaml` | ローカル開発環境（api + db + web）。本番は Coolify なので使わない |

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

前提: Docker / Docker Compose v2。ホストに Ruby や PostgreSQL は要らない。

```bash
cp .env.example .env      # ポートを変えたいときだけ編集する
docker compose up -d      # 初回は gem / npm の導入で数分かかる
docker compose logs -f api
```

| | URL |
| --- | --- |
| 予約 API | http://localhost:3011 |
| Swagger UI（API 仕様） | http://localhost:3011/docs |
| 参照実装 UI | http://localhost:3012/booking |
| PostgreSQL | `localhost:55432`（postgres / postgres） |

既定のポートを 3000 / 3001 からずらしてあるのは衝突を避けるため。空いていれば `.env` で戻せる。
Google 未連携でも動く（Busy 時間は空・予定は作成されない）。確認メールは SMTP へ送らず
`api/tmp/mails/` にファイル出力される。Google 連携とカレンダー選択は
http://localhost:3011/v1/admin/google/setup（手順は [`docs/DEPLOY.md`](docs/DEPLOY.md)）。

```bash
docker compose down       # 停止（DB データは残る）
docker compose down -v    # 停止 + DB データ削除
```

詳細な意思決定は [`docs/plans/2026-07-30-local-compose.md`](docs/plans/2026-07-30-local-compose.md)。

## テスト

```bash
docker compose exec -e RAILS_ENV=test api bin/rails test   # 176 件
docker compose exec web npm test                           # 15 件
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
POST               /v1/admin/google/oauth/url          # 同意画面の URL を発行
GET                /v1/admin/google/oauth/callback     # 同意後の戻り先（state 署名で検証）
GET                /v1/admin/google/calendars          # 連携アカウントのカレンダー一覧
GET|POST           /v1/admin/google/setup              # カレンダー設定画面（HTML）
POST               /v1/admin/google/disconnect         # 連携解除
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
