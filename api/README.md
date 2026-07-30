# api — slot-relay 予約 API

Ruby on Rails 8.1（API モード）+ PostgreSQL 16。
仕様の一次情報はリポジトリ最上位の [`docs/DESIGN.md`](../docs/DESIGN.md)。

## セットアップ

推奨はリポジトリ最上位からの Docker Compose（ホストに Ruby・PostgreSQL が要らない）。

```bash
cd .. && docker compose up -d      # api は http://localhost:3011
```

ホストに Ruby 3.3 / PostgreSQL 16 が揃っているなら直接でもよい。

```bash
bin/setup            # bundle install + DB 作成・マイグレーション
bin/rails db:seed    # 開発用の予約メニュー（genba-tsunagu-consultation）
bin/rails server -p 3001
```

環境変数は `.env.example` を参照（`dotenv-rails` が development / test で `.env` を読む）。
Google が未連携なら development では `GoogleCalendar::NullClient` が使われ、
Busy 時間は空・予定は作成されない。**本番では `UnavailableClient` になり 502 を返す**
（黙って「全部空き」にしないため）。連携手順は `docs/DEPLOY.md`。

## テスト

```bash
bin/rails test              # 全 176 件
bin/rails test test/services/availability_calculator_test.rb
bin/ci                      # setup + 依存監査 + テスト + seed

# compose 経由
docker compose exec -e RAILS_ENV=test api bin/rails test
```

- 外部 HTTP（Google Calendar / Cloudflare Turnstile）は WebMock で遮断している。
- Google クライアントは `SlotRelay.calendar_client` に `FakeCalendarClient` を注入して差し替える。
- 二重予約のテスト（`test/integration/double_booking_test.rb`）は実スレッド・別コネクションで
  検証するため、そのクラスだけ `use_transactional_tests = false`。

## PostgreSQL への依存

このアプリは PostgreSQL 固有機能に依存している（他の RDBMS へは移植できない）。

- `btree_gist` 拡張 + `EXCLUDE USING gist` で有効な予約の時間帯の重なりを禁止する
- `datetime` カラムは `timestamptz`（`config/initializers/timestamptz.rb`）。
  `timestamp without time zone` だと `tstzrange` の GiST インデックスを作れない

## 主要なディレクトリ

```
app/controllers/v1/public/   公開 API（無認証・Origin 検証 + Turnstile + レートリミット）
app/controllers/v1/admin/    管理 API（X-Admin-Key）
app/services/                空き枠計算・予約処理・Google 連携・OpenAPI ドキュメント
app/serializers/             JSON 表現（camelCase）
lib/slot_relay.rb            環境変数と外部依存の差し替えポイント
db/migrate/                  排他制約は 20260730000006_create_reservations.rb
```

読み進める順序は [`docs/CODE_READING.md`](../docs/CODE_READING.md)。

## rake タスク

```bash
bin/rails reservations:sweep_expired_pending   # 期限切れの仮確保を削除
bin/rails reservations:stats                   # 予約の状態別件数
```

## API 仕様

- `GET /openapi.json` — OpenAPI 3.1（`app/services/openapi_document.rb` が生成）
- `GET /docs` — Swagger UI
