# INTEGRATION.md — 予約フォームを作る人向けの手引き

このドキュメントは、**自分のサイトに予約フォームを実装する人**のためのものです。
予約 API（slot-relay）の運用者から連携を依頼されたら、まずここを読んでください。

- 触れる API 仕様: `https://<APIのドメイン>/docs`（Swagger UI）
- 参照実装: [`web/`](../web/) — Next.js のサンプル。そのまま真似できます

> 運用側（デプロイ・Google 連携）の手順は [`DEPLOY.md`](DEPLOY.md)、
> 設計の一次情報は [`DESIGN.md`](DESIGN.md) にあります。

## 1. 全体像

```
  あなたのサイト（ブラウザ）
        │  ① 空き枠を取得       GET  /v1/public/.../availability
        │  ② 予約を登録         POST /v1/public/.../reservations
        ▼
  予約 API（slot-relay）
        │  Google カレンダーの予定を見て空きを計算
        │  予約が確定したらカレンダーに予定を作成し、確認メールを送る
        ▼
  Google カレンダー
```

**あなたが実装するのは予約画面だけ**です。空き枠の計算・二重予約の防止・
カレンダーへの登録・確認メールの送信は、すべて API 側が行います。

## 2. 受け取る値

運用者から次の 3 つを受け取ります。**3 つとも公開してよい値**で、
ブラウザに埋め込まれる前提です。

| 値 | 例 | 用途 |
| --- | --- | --- |
| API の URL | `https://booking-api.example.net` | リクエスト先 |
| 予約メニューの slug | `genba-tsunagu-consultation` | どの予約枠か |
| Turnstile の **Site Key** | `0x4AAA...` | Bot 対策ウィジェットの描画 |

Next.js なら `NEXT_PUBLIC_*` に置きます（ビルド時に埋め込まれるので、
変更したら再ビルドが必要）。

```
NEXT_PUBLIC_BOOKING_API_URL=https://booking-api.example.net
NEXT_PUBLIC_BOOKING_TYPE=genba-tsunagu-consultation
NEXT_PUBLIC_TURNSTILE_SITE_KEY=0x4AAA...
```

### 受け取らない値

次のものは**渡されませんし、要求もしないでください**。サイト側に秘密を置かないのが
この API の設計です（[`DESIGN.md §5.2`](DESIGN.md)）。

- `ADMIN_API_KEY` — 管理 API の鍵。全予約者の個人情報が読めてしまいます
- `TURNSTILE_SECRET_KEY` — Site Key とは別物。サーバー側だけが持ちます
- Google の認証情報

**公開 API に API キーはありません。** 鍵の代わりに Turnstile・レートリミット・
許可 Origin で守っています。

## 3. 連携前に運用者がやること

サイトのオリジンを**許可 Origin に登録**してもらってください。
ここが漏れていると、あなたのリクエストはすべて `403 FORBIDDEN_ORIGIN` になります。

```
https://your-site.example.com
```

本番・ステージング・プレビュー環境でオリジンが違うなら、**全部**登録が必要です。
ローカル開発で `http://localhost:3000` から叩くなら、それも登録してもらいます。

## 4. 実装の流れ

### ① 予約メニューを取得する（任意）

画面に名前や所要時間を出すために使います。

```bash
curl "https://booking-api.example.net/v1/public/booking-types/genba-tsunagu-consultation"
```

```json
{
  "slug": "genba-tsunagu-consultation",
  "name": "無料相談",
  "description": "業務自動化についての無料相談（60 分）",
  "durationMinutes": 60,
  "timeZone": "Asia/Tokyo",
  "minimumNoticeMinutes": 1440,
  "bookingWindowDays": 30
}
```

- `minimumNoticeMinutes` — 何分前まで予約を受け付けるか（1440 = 24 時間前まで）
- `bookingWindowDays` — 何日先まで予約できるか

### ② 空き枠を取得する

```bash
curl "https://booking-api.example.net/v1/public/booking-types/genba-tsunagu-consultation/availability?from=2026-08-03&to=2026-08-09"
```

```json
{
  "timeZone": "Asia/Tokyo",
  "durationMinutes": 60,
  "days": [
    { "date": "2026-08-03", "slots": [
      { "startAt": "2026-08-03T10:00:00+09:00", "endAt": "2026-08-03T11:00:00+09:00" },
      { "startAt": "2026-08-03T11:00:00+09:00", "endAt": "2026-08-03T12:00:00+09:00" }
    ] },
    { "date": "2026-08-04", "slots": [] }
  ]
}
```

- `from` / `to` は `YYYY-MM-DD`。**両端を含みます**（`from=to` なら 1 日分）
- どちらも省略できます。`from` の既定は今日、`to` の既定は `from` から **14 日間**
- **1 回に取得できるのは最大 62 日**。超えると `400 INVALID_RANGE`。
  `to` が `from` より前でも同じエラーです
- 空きが無い日も `"slots": []` で返るので、「休業日」と「範囲外」を区別できます。
  カレンダー UI で「予約できない日」を描画するのに使えます
- `startAt` / `endAt` は予約メニューのタイムゾーンでのオフセット付き ISO 8601 です。
  `new Date(startAt)` でそのまま扱えます

### ③ 予約を登録する

```bash
curl -X POST "https://booking-api.example.net/v1/public/booking-types/genba-tsunagu-consultation/reservations" \
  -H "Content-Type: application/json" \
  -H "Idempotency-Key: 0f9c2b1e-4d5a-4f21-9a3e-1b2c3d4e5f60" \
  -d '{
    "startAt": "2026-08-03T10:00:00+09:00",
    "guest": {
      "name": "山田 太郎",
      "email": "taro@example.com",
      "company": "株式会社サンプル",
      "phone": "090-0000-0000"
    },
    "answers": { "相談内容": "日報業務を自動化したい" },
    "turnstileToken": "0.xxxxx"
  }'
```

| 項目 | 必須 | 備考 |
| --- | --- | --- |
| `Idempotency-Key`（ヘッダ） | **必須** | 次章参照。無いと `422` |
| `startAt` | 必須 | ② で得た `startAt` をそのまま送る |
| `guest.name` / `guest.email` | 必須 | |
| `guest.company` / `guest.phone` | 任意 | |
| `answers` | 任意 | 自由項目。キーは自由な文字列 |
| `turnstileToken` | 実質必須 | Turnstile が有効な環境では無いと `403` |

成功すると `201` で予約が返ります。`cancelUrl` はこのときだけ含まれます
（確認メールにも同じ URL が載ります）。

```json
{
  "reservationId": "res_xxxxxxxx",
  "status": "confirmed",
  "startAt": "2026-08-03T10:00:00+09:00",
  "endAt": "2026-08-03T11:00:00+09:00",
  "cancelUrl": "https://.../c/res_xxxxxxxx/<token>"
}
```

## 5. Idempotency-Key の規則

**ここが一番間違えやすい場所です。**

通信が不安定なときに「送信したが応答が届かない」状況が起きます。利用者が再送したときに
二重予約にならないよう、同じキーで送られたリクエストは**新しい予約を作らず、
最初に作った予約をそのまま返します**。

規則は 3 つです。

1. **予約 1 回につき 1 つ発行する。** 入力を終えて送信ボタンを押せる状態になった時点で作る
2. **送信失敗して再送するときは、同じキーを使う。** これが二重予約を防ぐ仕組みです
3. **`409 SLOT_UNAVAILABLE` で選び直したら、新しいキーを発行する。** 別の枠を選んだのは
   「新しい予約試行」なので、キーを使い回してはいけません

**暗号論的乱数から作ってください。** このキーは「予約作成の応答を再取得できる合言葉」
として働くため、推測されると他人の予約内容を読まれます。

```ts
crypto.randomUUID()   // これでよい
Date.now().toString() // 絶対にだめ
```

実装例は [`web/lib/bookingApi.ts`](../web/lib/bookingApi.ts) の `newIdempotencyKey()`。

同じキーのリクエストが**同時に**届いた場合は `409 REQUEST_IN_PROGRESS` が返ります。
少し待って再試行してください。

## 6. Turnstile の組み込み

Bot による自動予約を防ぐため、予約 POST には Cloudflare Turnstile のトークンが要ります。

```html
<script src="https://challenges.cloudflare.com/turnstile/v0/api.js" async defer></script>
<div class="cf-turnstile" data-sitekey="0x4AAA..." data-callback="onTurnstileToken"></div>
```

コールバックで受け取ったトークンを、予約 POST の `turnstileToken` に載せます。

- **トークンは 1 回しか使えません。** 予約が失敗して送り直すときは、
  ウィジェットをリセットして新しいトークンを取り直してください
  （`turnstile.reset()`）
- トークンには有効期限（数分）があります。フォーム表示から送信まで時間が空くと
  失効するので、送信直前に取得するか、失効時のコールバックで取り直します

明示的に描画する実装例は [`web/components/TurnstileWidget.tsx`](../web/components/TurnstileWidget.tsx)。

## 7. エラー応答

エラーはすべてこの形です。

```json
{ "code": "SLOT_UNAVAILABLE", "message": "選択された時間は利用できなくなりました。", "details": ["..."] }
```

`message` はそのまま利用者に見せられる日本語です。`details` は入力エラーのときだけ入ります。

| HTTP | `code` | 意味 | 画面での扱い |
| --- | --- | --- | --- |
| 400 | `INVALID_RANGE` | `from`/`to` の期間が不正・広すぎ | 実装側のバグ。期間を狭める |
| 400 | `BAD_REQUEST` | 必須パラメータ不足 | 実装側のバグ |
| 403 | `FORBIDDEN_ORIGIN` | 許可 Origin に入っていない | **運用者にオリジンの登録を依頼** |
| 403 | `TURNSTILE_FAILED` | Bot 判定に失敗 | ウィジェットをリセットして再取得を促す |
| 404 | `NOT_FOUND` | slug が違う・メニューが無効 | 設定値を確認 |
| 409 | `SLOT_UNAVAILABLE` | 枠が埋まった | **空き枠を取り直して選び直させる。キーも新規発行** |
| 409 | `REQUEST_IN_PROGRESS` | 同じキーの処理が進行中 | 少し待って再試行 |
| 422 | `VALIDATION_FAILED` | 入力エラー | `details` を項目ごとに表示 |
| 422 | `INVALID_START_AT` | `startAt` の形式・値が不正 | 枠を選び直させる |
| 429 | `RATE_LIMITED` | リクエスト過多 | 時間をおいて再試行 |
| 502 | `CALENDAR_ERROR` | Google カレンダーに繋がらない | 「時間をおいて」と案内。運用者に連絡 |
| 503 | `CONFIGURATION_ERROR` | API 側の設定不足 | 運用者に連絡 |

**`409 SLOT_UNAVAILABLE` の扱いだけは必ず実装してください。** 予約フォームでは
「選んでいる間に他の人に取られる」が普通に起きます。エラーを出して終わりにせず、
空き枠を取り直して選び直せる導線に戻します。実装例は
[`web/components/BookingForm.tsx`](../web/components/BookingForm.tsx)。

## 8. 予約の照会・キャンセル

確認メールに載せた**キャンセル URL のトークン**を持っている人だけが使えます。
予約 ID（`res_xxx`）を知っているだけでは読めません。

```
GET  /v1/public/reservations/:token
POST /v1/public/reservations/:token/cancel
```

サイト側にキャンセル画面を置く場合は、運用者に `CANCEL_URL_BASE` を
あなたのサイトの URL に設定してもらってください。メールのリンクがそこを指すようになります。
実装例は [`web/app/c/[publicId]/[token]/page.tsx`](../web/app/c/) と
[`web/components/CancelPanel.tsx`](../web/components/CancelPanel.tsx)。

## 9. 詰まったときの切り分け

| 症状 | 疑うところ |
| --- | --- |
| 全部 `403 FORBIDDEN_ORIGIN` | 許可 Origin の登録漏れ。プレビュー環境のオリジンも忘れやすい |
| 予約だけ `403 TURNSTILE_FAILED` | トークンの使い回し・失効。送信のたびに取り直す |
| 予約だけ `503` | API 側の Turnstile 設定漏れ。運用者に連絡 |
| 空き枠が全部空 | Google 連携が切れている可能性。運用者に連絡 |
| 今日・明日が出ない | 仕様です。`minimumNoticeMinutes`（既定 24 時間前まで）を確認 |
| 土日が出ない | 仕様です。受付時間は運用者が曜日別に設定します |

エラーが再現する `code` と時刻を運用者に伝えると、サーバーログから追えます。
