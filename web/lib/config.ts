/**
 * サイト側に置く設定はこれだけ。
 * Google の認証情報や管理 API キーはサイト側に置かない（docs/DESIGN.md §5.2）。
 */
export const bookingApiUrl =
  process.env.NEXT_PUBLIC_BOOKING_API_URL ?? "http://localhost:3001";

export const bookingTypeSlug =
  process.env.NEXT_PUBLIC_BOOKING_TYPE ?? "genba-tsunagu-consultation";

/** 未設定なら Turnstile ウィジェットを描画しない（ローカル開発向け） */
export const turnstileSiteKey = process.env.NEXT_PUBLIC_TURNSTILE_SITE_KEY ?? "";
