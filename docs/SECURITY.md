# SECURITY.md — セキュリティ懸念事項

> ルール: 新機能・変更でセキュリティ上の懸念が生じたら、必ず本ドキュメントに追記する（CLAUDE.md 参照）。
> 各項目は「懸念｜対策方針｜状況」の 3 列で管理し、対策を実装したら「状況」列を更新する。
> 状況の値は **対応済み / 一部対応 / 未実装 / 運用ルール化** から選ぶ。

## 前提となる脅威モデル

公開 API（`/v1/public/...`）は**無認証で誰でも叩ける**。予約サイトのブラウザから直接呼ぶため、
秘密の API キーをサイト側に置けない。したがって次の 5 つを**併用**して守る（DESIGN §5.2）。

1. 予約メニューごとの許可 Origin 検証
2. IP 単位のレートリミット
3. Cloudflare Turnstile（予約 POST）
4. 入力検証（型・長さ・件数）
5. Idempotency-Key

**CORS は防御に数えない。** HTTP クライアントは Origin ヘッダを偽装できる。

## 1. 外部からの入力

| 懸念 | 対策方針 | 状況 |
|---|---|---|
| Bot による自動予約 | 予約 POST に Cloudflare Turnstile を必須化。Cloudflare 側の障害時は fail closed（弾く）。ただし**既存 Idempotency-Key の再送は Turnstile を再検証しない**（トークンが単回使用のため。新しい予約は作られないので Bot 対策は迂回されない） | 対応済み（本番で `TURNSTILE_SECRET_KEY` の設定が必要） |
| 空き枠 API の総なめ・大量リクエスト | rack-attack で IP 単位のレートリミット（公開 120req/60s、予約 POST・キャンセル 5req/600s、管理 60req/60s）。429 に `Retry-After` を付ける | 対応済み |
| 再送・多重送信による二重予約 | `Idempotency-Key` を必須化。同一キーは先着の予約を返す（`(booking_type_id, idempotency_key)` に部分一意インデックス） | 対応済み |
| 同時リクエストによる二重予約 | DB の `EXCLUDE USING gist` で有効な予約（pending/confirmed）の重なりを禁止。スコープは**登録先 Google カレンダー単位**（予約メニュー単位だと同じカレンダーを共有する別メニューがすり抜ける）。実スレッドでの同時実行テストあり | 対応済み |
| Idempotency-Key の推測による他人の予約情報の閲覧 | 同じキーの再送には作成済み予約（氏名・メール等を含む）を返すため、キーは実質ベアラトークン。クライアントは暗号論的乱数で生成する（参照実装は `crypto.randomUUID` / `getRandomValues`）。加えて予約 POST のレートリミット（既定 5req/600s）が総当たりを抑える | 一部対応（キーの品質はクライアント側の責任） |
| パラメータ汚染（配列・オブジェクトを文字列カラムへ） | 公開 API はマスアサインメントせず、`String` 以外を `nil` に落としてから検証する | 対応済み |
| 巨大 JSON（`answers`）でのリソース消費 | キー数 30・値 2000 文字・コレクション要素 200 の上限を検証 | 対応済み |
| 空き枠取得の期間指定による重い処理 | 1 リクエスト最大 62 日（`AvailabilityCalculator::MAX_RANGE_DAYS`）。超過は 400 | 対応済み |
| 許可していないサイトからのブラウザ利用 | 予約メニューごとの許可 Origin と厳密一致で検証（不一致は 403）。プリフライトは全メニューの Origin 集合で判定 | 対応済み |
| Host ヘッダ攻撃・DNS リバインディング | `ALLOWED_HOSTS` を設定した場合に `config.hosts` で検証（ヘルスチェックパスは除外） | 一部対応（`ALLOWED_HOSTS` の設定が必要） |
| 外部 Webhook の偽装リクエスト | Webhook は受け取らない（Google Calendar Webhook は MVP 対象外） | 該当なし |

### レートリミットの既知の限界

カウンタは各プロセスのメモリ（`ActiveSupport::Cache::MemoryStore`）に持つ。
**Puma を複数ワーカーで動かすとワーカー数ぶん制限が緩くなる。** 単一コンテナ・単一プロセス運用を
前提とした割り切り。インスタンスを増やすときは Redis 等の共有ストアへ移すこと（DESIGN §14）。

## 2. 認証・認可

| 懸念 | 対策方針 | 状況 |
|---|---|---|
| 管理 API のなりすまし | `X-Admin-Key` ヘッダ。比較は `ActiveSupport::SecurityUtils.secure_compare`（タイミング攻撃対策） | 対応済み |
| 管理キー未設定で API が開いてしまう | 未設定または 32 文字未満なら **503** を返す（「未設定なら通る」状態を作らない） | 対応済み |
| 管理キーの総当たり | 管理 API にもレートリミット（既定 60req/60s） | 対応済み |
| 越権・IDOR（他人の予約の参照・キャンセル） | 予約の照会・キャンセルは**生のキャンセルトークン**でのみ認可。`public_id` からは引けない | 対応済み |
| キャンセルトークンの漏洩・DB 流出 | DB には SHA-256 ハッシュのみ保存。生の値は発行時のメモリとメール本文だけ | 対応済み |
| キャンセルトークンの推測 | `SecureRandom.urlsafe_base64(32)`（256 bit） | 対応済み |
| CORS | 予約メニューごとの許可 Origin を DB で管理し、レスポンスに `Vary: Origin` を付ける。CORS 自体は防御に数えない | 対応済み |
| OAuth コールバックが無認証で叩かれる | コールバックは Google からのリダイレクトで `X-Admin-Key` を付けられない。代わりに `state` を署名付きトークン（10 分で失効）にして検証する。有効な `state` の発行には管理キーが要る | 対応済み |
| 設定画面のセッション悪用 | 同意直後に発行する Cookie は **HttpOnly / SameSite=Strict / 30 分失効 / path=`/v1/admin/google`**、production では Secure | 対応済み |
| 設定画面への CSRF | Cookie で認証する唯一の画面のため、POST は署名付き CSRF トークン（セッションの nonce に紐づく）を必須にする。`X-Admin-Key` 経由はブラウザが自動送信しないため対象外 | 対応済み |
| 管理キーが URL に載る | 設定画面のログインは**フォームの POST ボディ**で管理キーを受け取り、短期セッション Cookie に引き換える。クエリには置かない。設定画面には `<meta name="referrer" content="no-referrer">` と `noindex` を付ける | 対応済み |
| 設定画面ログインの総当たり | `/v1/admin` 配下のレートリミット（既定 60req/60s）が効く。比較は `secure_compare`。失敗は IP つきでログに残す | 対応済み |

## 3. シークレット管理

| 懸念 | 対策方針 | 状況 |
|---|---|---|
| API キー・認証情報の漏洩 | リポジトリに平文で置かない。すべて Coolify の環境変数。`.env` は `.gitignore` 済み（`.env.example` は値なし） | 対応済み |
| Google の認可コード・トークンのログ流出 | `config.filter_parameters` に `code` / `state` / `refresh_token` / `access_token` / `client_secret` / `GOOGLE_OAUTH_CLIENT_SECRET` を追加。Google API のエラーは Google 由来のメッセージのみログに残す | 対応済み |
| **refresh token の DB 流出** | 平文で保存しない。`SECRET_KEY_BASE` から `key_generator` で導出した鍵の `ActiveSupport::MessageEncryptor` で暗号化して保存する。API 応答・設定画面には暗号文も含めて出さない（テストで検証） | 対応済み |
| refresh token の暗号鍵の管理 | `SECRET_KEY_BASE` に相乗りしている。ActiveRecord Encryption を使うと production 必須の環境変数が 3 本増えるため（`docs/plans/2026-07-30-google-oauth-calendar-selection.md`）。**`SECRET_KEY_BASE` を回すと復号できなくなり、Google の再連携が必要**。復号失敗時は例外にせず「未連携」として扱い、502 で気づけるようにしている | 対応済み（運用注意） |
| API 仕様書からの秘密情報の漏洩 | `/openapi.json` に管理キー・秘密鍵・SMTP 情報を含めない（テストで検証） | 対応済み |
| CI からの漏洩 | GitHub Secrets を使用。ログへのエコー禁止。CI では実シークレットを使わない | 運用ルール化 |
| Docker イメージへのシークレット同梱 | `.dockerignore` で `.env` を除外。秘密は実行時の環境変数のみ | 対応済み |
| Rails 暗号化 credentials の鍵管理 | 暗号化 credentials は使わない（`credentials.yml.enc` / `master.key` を置かない）。秘密は環境変数に一本化し、production では `SECRET_KEY_BASE` を設定する | 対応済み |

## 4. ユーザーデータ・プライバシー

| 懸念 | 対策方針 | 状況 |
|---|---|---|
| 予約者の個人情報のログ流出 | `config.filter_parameters` に `guest` / `name` / `email` / `company` / `phone` / `answers` / `turnstileToken` を追加 | 対応済み |
| Google カレンダーの個人予定の内容が API へ流れる | 空き判定は **FreeBusy API のみ**。件名・説明・参加者は取得しない | 対応済み |
| **OAuth 化による権限分離の後退** | サービスアカウント時代は個人カレンダーを「予定の時間枠のみ表示」で共有し、**資格情報そのものが内容を読めなかった**。ユーザー OAuth では 1 つの資格情報に権限が集まるため、`calendar.events` スコープを持つトークンは予定の内容を読めてしまう。コードは FreeBusy しか呼ばないが、多層防御としては明確な後退。全権の `calendar` を避けて 3 つの最小スコープに分ける対策までにとどめている | **受容したリスク**（`docs/plans/2026-07-30-google-oauth-calendar-selection.md`） |
| Google 連携が切れて「全部空き」になる | 未連携・トークン失効時は `GoogleCalendar::UnavailableClient` が 502 を返す。`NullClient`（空の Busy を返す）は development のみ | 対応済み |
| Google 予定の内容が公開 API へ漏れる | 公開 API の応答は `timeZone` / `durationMinutes` / `days`（`date` と `startAt` / `endAt`）のみ。テストで検証 | 対応済み |
| 内部設定の漏洩（バッファ・カレンダー ID） | 公開ペイロードから除外（`BookingTypeSerializer.public_payload`）。テストで検証 | 対応済み |
| 個人情報の取り扱い・アクセス最小化 | 保持するのは氏名・メール・会社名・電話・`answers` のみ。管理 API とトークン保持者以外は読めない | 対応済み |
| 関連データの残存 | 予約メニュー削除時に受付時間・許可 Origin・オーバーライドを連鎖削除。予約がある場合は削除を拒否 | 対応済み |
| 予約データの保持期間 | 未定。過去予約の自動削除は実装していない | 未実装 |

## 5. データベース・インフラ

| 懸念 | 対策方針 | 状況 |
|---|---|---|
| PostgreSQL の外部公開 | Coolify の内部ネットワークのみ。外部ポートを開けない | 運用ルール化（`docs/DEPLOY.md`） |
| データ消失 | Coolify の日次バックアップ + 保持期間の設定 | 未設定（デプロイ時に設定する） |
| コンテナの root 実行 | Dockerfile で非 root ユーザー（uid 1000）に切り替える | 対応済み |
| 通信の平文化 | Coolify のリバースプロキシで TLS 終端。`force_ssl` + HSTS を有効化 | 対応済み |
| 起動時の設定漏れに気づけない | 本番で必須環境変数が欠けていれば起動時に警告ログを出す。Google 未設定なら例外で落とす | 対応済み |

## 6. サプライチェーン・依存関係

| 懸念 | 対策方針 | 状況 |
|---|---|---|
| 依存パッケージの脆弱性 | CI で `bundler-audit`（Ruby）を実行。Dependabot も有効 | 対応済み |
| npm 依存の脆弱性 | Dependabot。CI では型チェック・テスト・ビルドを実行 | 一部対応（`npm audit` は CI に入れていない） |
| サードパーティ CI アクション | 公式アクション優先。サードパーティはコミット SHA でピン留め | 運用ルール化 |
| Swagger UI を CDN（unpkg）から読み込む | `/docs` は仕様閲覧用の画面のみ。API の認可には関与しない。バージョンを固定して読み込む | 一部対応（自前ホスティングは未実施） |

## 7. LLM 特有のリスク

このプロダクトは LLM を組み込んでいないため該当なし。将来 LLM を使う場合は、
プロンプトインジェクション・出力の未信頼扱い・ログへの機微情報混入・コスト暴走を本節に追記する。

## 更新ルール

- 機能追加・変更の PR では、本ドキュメントの該当セクションを見直し、新しい懸念があれば追記する
- 対策を実装したら「状況」列を更新する
