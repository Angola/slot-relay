# web — 予約フォームの参照実装

Next.js 15（App Router）+ React 19 + TypeScript。

**これは本番デプロイ対象ではない。** 予約 API の公開エンドポイントだけで予約画面が成立することを示し、
画面遷移をテストで固定するために置いている。実際の予約画面は各サイト（genba-tsunagu.jp など）が
自前のデザインで実装し、同じ API を呼ぶ（[`docs/DESIGN.md §2.1`](../docs/DESIGN.md)）。

## セットアップ

```bash
npm install
cp .env.example .env.local   # ローカルの API を指す（http://localhost:3001）
npm run dev                  # http://localhost:3000
```

API 側で `bin/rails db:seed` を実行し、許可 Origin に `http://localhost:3000` が
入っていることを確認する（seed に含まれている）。

## 画面

| パス | 内容 |
| --- | --- |
| `/` | 設定の確認と予約画面への導線 |
| `/booking` | 予約フォーム（日付選択 → 時間選択 → 入力 → Turnstile → 完了） |
| `/c/[publicId]/[token]` | キャンセル画面（確認メールの URL から開く） |

## サイト側に置く設定

これだけ。Google の認証情報や管理 API キーは置かない。

```
NEXT_PUBLIC_BOOKING_API_URL=https://booking-api.genba-tsunagu.jp
NEXT_PUBLIC_BOOKING_TYPE=genba-tsunagu-consultation
NEXT_PUBLIC_TURNSTILE_SITE_KEY=
```

`NEXT_PUBLIC_TURNSTILE_SITE_KEY` が未設定なら Turnstile ウィジェットを描画しない。

## テスト

```bash
npm test           # vitest（API クライアント + 画面遷移）
npm run typecheck
npm run build
```

## 実装で参考にするところ

- `lib/bookingApi.ts` — 公開 API のクライアント。`Idempotency-Key` の発行と
  エラー応答（`{ code, message, details }`）の扱いが要点
- `components/BookingForm.tsx` — 枠が埋まっていた場合（409 `SLOT_UNAVAILABLE`）に
  選び直しへ戻し、空き枠を再取得して**新しい Idempotency-Key** で送り直す流れ
