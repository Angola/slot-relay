# Google 連携をサービスアカウントから OAuth へ移行し、カレンダーを画面で選べるようにする

- 日付: 2026-07-30
- ブランチ: `feat/google-oauth-calendar-selection`

## やりたいこと

1. Google カレンダー連携の認証を**サービスアカウントからユーザー OAuth（refresh token）へ切り替える**
2. 連携後に、**空き判定に使うカレンダー／予約の登録先カレンダーを画面から選べる**ようにする

## 背景・なぜ

### そもそもサービスアカウントを選んでいた理由

`DESIGN.md §6.1` の判断はこうだった。

> 利用者が自分だけなので、一般ユーザー向けの Google OAuth は実装しない。

この API は誰もログインしていない状態で予約を書き込む無人サーバーなので、
運用の堅さだけを見ればサービスアカウントが正しい。OAuth に移ると次を失う。

- **refresh token の失効リスクを負う。** 同意画面が「テスト中」のままだと 7 日で失効する。
  パスワード変更・6 か月未使用・手動失効でも死ぬ。サービスアカウントにはこの failure mode が無い
- **カレンダーの権限分離が崩れる。** 現状は個人カレンダーを「予定の時間枠のみ表示」で共有し、
  件名や内容を API サーバーへ渡していない。OAuth では 1 つの資格情報に権限が集約される

### それでも OAuth にする理由

上記を説明したうえで OAuth を選ぶ判断をした。得られるものは以下。

- **ゲストに Google カレンダーの招待を送れる。** サービスアカウントはドメイン全体の委任なしに
  招待を送れず、現状は `attendees` を諦めている（`DESIGN.md §6.1`）
- **予定の主催者が本人名義になる。** 現状はサービスアカウントが作成者として表示される
- **カレンダーを個別共有しなくてよい。** 連携するだけで自分の全カレンダーが対象になり、
  「どのカレンダーを使うか」を後から画面で選べる ← 今回の主題

つまり移行の動機は「簡単さ」ではなく**できることが増えること**。運用リスクは受け入れる。

## 方針

### 認証（サービスアカウントは廃止し、置き換える）

両方を残すと設定の分岐とテストが倍になるため、**置き換え**とする。
`GOOGLE_SERVICE_ACCOUNT_EMAIL` / `GOOGLE_SERVICE_ACCOUNT_PRIVATE_KEY` は削除し、
代わりに以下を追加する。

| 変数名 | 用途 |
| --- | --- |
| `GOOGLE_OAUTH_CLIENT_ID` | OAuth クライアント（種別: ウェブアプリケーション） |
| `GOOGLE_OAUTH_CLIENT_SECRET` | 同上 |
| `GOOGLE_OAUTH_REDIRECT_URI` | 省略時は `PUBLIC_BASE_URL` + コールバックパス |

`GOOGLE_BUSY_CALENDAR_IDS` / `GOOGLE_BOOKING_CALENDAR_ID` は**環境変数での指定をやめ、
DB（画面から選択）へ移す**。移行期の互換のため、DB が空のときだけ環境変数を既定値として読む。

### スコープは最小権限にする

現状は `https://www.googleapis.com/auth/calendar`（全権）1 本だが、必要な操作は 3 つなので分ける。

| スコープ | 用途 |
| --- | --- |
| `calendar.calendarlist.readonly` | カレンダー一覧の取得（選択画面） |
| `calendar.freebusy` | 空き判定（FreeBusy のみ。予定の件名・説明は取らない） |
| `calendar.events` | 予約の予定を作成・削除する |

`calendar.events` は予定の内容を読める権限を含むため、「予定の時間枠のみ表示」共有ほどの
分離にはならない。この後退は `SECURITY.md` に明記する。

### refresh token の保存

**DB に保存し、`SECRET_KEY_BASE` 由来の鍵で暗号化する**（`ActiveSupport::MessageEncryptor`）。

ActiveRecord Encryption ではなく MessageEncryptor を選んだ理由は、AR Encryption だと
本番に必須の環境変数が 3 本増えるため。`SECRET_KEY_BASE` は既に production 必須なので、
これを鍵導出元にすれば新しい秘密を増やさずに済む。
副作用として **`SECRET_KEY_BASE` を回すと再連携が必要**になる。これは `SECURITY.md` に書く。

テーブルは単一行の `google_connections`（連携アカウントは 1 つだけ）。

### 連携フロー

管理 API キーを URL に載せないため、開始は「API で認可 URL を発行 → ブラウザで開く」の 2 段にする。

```
1. POST /v1/admin/google/oauth/url        (X-Admin-Key)  → { authUrl }
2. ブラウザで authUrl を開き、Google の同意画面を通す
3. GET  /v1/admin/google/oauth/callback?code=&state=     → refresh token を保存
4. 設定画面へリダイレクト（短期セッション Cookie を発行）
```

`state` は `ActiveSupport::MessageVerifier` の署名付きトークン（10 分で失効）。
DB もキャッシュも使わず、改ざんは署名で弾く。攻撃者が有効な `state` を作るには
管理 API キーが要るため、これで足りる。

### 設定画面

`GET /v1/admin/google/setup`。サーバー描画の HTML（`DocsController` が Swagger UI の HTML を
返している前例に倣う）。

- 認証は**コールバックで発行した短期セッション Cookie**（30 分・HttpOnly・SameSite=Strict、
  production では Secure）。`X-Admin-Key` でも開ける
- 保存は同一画面からの POST。CSRF は SameSite=Strict に加えて署名付きトークンをフォームに埋める
- 予約メニューごとに「登録先カレンダー（ラジオ）」「空き判定に使うカレンダー（チェックボックス）」を出す
- 連携の解除もここから行う

### データモデルの変更

| 変更 | 内容 |
| --- | --- |
| 追加 | `google_connections`（`google_account_email` / `encrypted_refresh_token` / `scopes` / `connected_at`） |
| 追加 | `booking_types.google_busy_calendar_ids`（`string[]`・既定 `[]`） |

`AvailabilityCalculator#busy_calendar_ids` は、メニュー単位の指定があればそれを使い、
無ければ従来どおり環境変数を見る。登録先カレンダー自身を必ず含める挙動は変えない。

## 経緯・メモ

- 「サービスアカウントのままにする／OAuth へ移る／調査だけ」を提示したうえで OAuth を選択。
  さらに「カレンダーを手動で選びたい」という要望を受け、選択 UI は
  **管理 API だけで済ませる案ではなく専用の設定画面を作る案**を採用した
  （認証経路と CSRF 対策が増えるが、ID を手で貼らずに済む UX を優先）。
- 招待メール（`attendees` + `sendUpdates`）は OAuth 化で**可能になる**が、今回のスコープには
  含めない。確認メールは既に自前 SMTP で送っており、挙動の変更は別途判断する。`MILESTONE.md` に残す。

## 積み残し

- 同意画面を「本番」に切り替えないと refresh token が 7 日で失効する。手順は `DEPLOY.md` に書く
- refresh token が失効したときの検知（連携切れの管理者通知）は未実装
- ゲストへの Google カレンダー招待（`attendees`）
