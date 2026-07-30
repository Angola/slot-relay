# 本番公開に向けて危うい既定値をなくす

- 日付: 2026-07-30
- ブランチ: `feat/harden-production-defaults`

## やりたいこと

Coolify で公開 URL に出す前に、次の 2 つを直す。

1. `TURNSTILE_SECRET_KEY` が未設定のとき、**Bot 検証を素通しにしない**
2. API ドキュメント（`/docs` / `/openapi.json`）を**本番では既定で閉じる**

## 背景・なぜ

公開の直前に「認証はどうなっているか」を洗い直したところ、2 点まずいところが見つかった。

### 1. Turnstile 未設定で予約が無防備になる

`TurnstileVerifier#verify` は `return true unless enabled?` で、
`TURNSTILE_SECRET_KEY` が未設定なら**常に成功**を返す。ローカル開発のための割り切りだが、
本番で設定を入れ忘れると気づけないまま公開されてしまう。

そのとき予約 POST の防御はレートリミット（既定 1 IP あたり 10 分に 5 件）だけになる。
IP を変えれば実質無制限にダミー予約を作れ、**Google カレンダーにゴミ予定が量産されて
枠が埋まる**。予約サイトとして致命的。

管理 API は「キー未設定なら 503」で「未設定なら通る」状態を作らない方針になっている
（`SECURITY.md` §2）。予約 POST も同じ扱いに揃えるのが筋。

### 2. 公開ドキュメントが管理 API の偵察を無料にする

`/openapi.json` に秘密情報は入っていない（テストで検証済み）ので、当初は
「仕様は公開情報」という判断だった。しかし OAuth 移行で状況が変わった。

- 管理 API のパス構成がすべて見える
- **`/v1/admin/google/setup` は誰でも開けるログインフォーム**になった。
  公開ドキュメントに載せるとスキャナに拾われ、総当たりの的になる
  （32 文字以上の鍵なので破られはしないが、ノイズは増える）
- `noindex` も付いておらず、検索エンジンにインデックスされる

鍵の強度が本当の防御なので即危険ではないが、多層防御としては損。
公開 API の利用者は他サイトの開発者なのでドキュメントに価値があるが、
管理 API の利用者は 1 人で、リポジトリかローカルで読める。

## 方針

### 起動は落とさない（重要）

「未設定なら起動を拒む」案もあったが採らない。理由は 2 つ。

- Turnstile 未設定のうちは `/v1/admin/google/setup` にも到達できず、**Google 連携ができない**。
  デプロイ直後は必ずこの状態なので、初回セットアップが詰む
- Coolify のヘルスチェックが落ちて**ロールバックループ**になる

既存方針（`config/initializers/slot_relay.rb` のコメント）どおり、
起動時は警告にとどめ、**拒否は各エンドポイントで行う**。

### 判定を `SlotRelay.config` に集約する

`Rails.env.production?` をサービスやコントローラに直接書くとテストで差し替えられない。
`Configuration` に真偽値として持たせ、`configure_slot_relay!` で上書きできるようにする。

| 追加する設定 | 既定値 |
| --- | --- |
| `require_turnstile` | `Rails.env.production?` |
| `api_docs_enabled` | `Rails.env.local?` または `ENABLE_API_DOCS=true` |

### 1. Turnstile

`Reservations::Creator` で、`require_turnstile` かつ未設定なら
`:configuration_error`（503）を返す。Idempotency-Key による既存予約の再送は
先に返るので、確定済みの予約の照会は 503 にならない。

キャンセル・照会は Turnstile の対象外（元からトークン認可）なので変えない。

### 2. API ドキュメント

`DocsController` で `api_docs_enabled` が false なら **404**（存在を隠す。403 だと
「ある」ことが分かる）。あわせて Swagger UI の HTML に `noindex, nofollow` を付ける。

本番で読みたいときは `ENABLE_API_DOCS=true` を入れれば開く。恒久的に開けるつもりなら、
公開 API だけ出す形（`admin` タグの除外）を別途検討する。

## 経緯・メモ

- 選択肢として「公開 API だけ出す」「本番では閉じる」「現状維持」を提示し、
  **「本番では閉じる」**を採用した。
- Turnstile は「起動を拒む」か「エンドポイントで 503」かを提示し、上記の理由で 503 にした。

## 積み残し

- 恒久的にドキュメントを公開したくなった場合の「`admin` タグだけ除外」実装
- `/health` `/ready` は無認証のまま（Coolify のヘルスチェックが叩くため）。
  返す情報はステータスとバージョンだけなので許容している
