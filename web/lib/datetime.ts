/**
 * 表示用の日時整形。API は予約メニューのタイムゾーンのオフセット付き RFC 3339
 * （例: 2026-08-03T10:00:00+09:00）を返すので、そのタイムゾーンで描画する。
 */

/** "2026-08-03" 形式（ローカル日付。API の from/to に渡す） */
export function toDateParam(date: Date): string {
  const year = date.getFullYear();
  const month = `${date.getMonth() + 1}`.padStart(2, "0");
  const day = `${date.getDate()}`.padStart(2, "0");
  return `${year}-${month}-${day}`;
}

export function addDays(date: Date, days: number): Date {
  const next = new Date(date);
  next.setDate(next.getDate() + days);
  return next;
}

/** "2026-08-03" → "8月3日(月)" */
export function formatDateLabel(isoDate: string, timeZone: string): string {
  const date = new Date(`${isoDate}T12:00:00Z`);
  return new Intl.DateTimeFormat("ja-JP", {
    month: "long",
    day: "numeric",
    weekday: "short",
    timeZone,
  }).format(date);
}

/** RFC 3339 → "10:00" */
export function formatTimeLabel(isoDateTime: string, timeZone: string): string {
  return new Intl.DateTimeFormat("ja-JP", {
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
    timeZone,
  }).format(new Date(isoDateTime));
}

/** RFC 3339 → "2026年8月3日(月) 10:00" */
export function formatDateTimeLabel(isoDateTime: string, timeZone: string): string {
  return new Intl.DateTimeFormat("ja-JP", {
    year: "numeric",
    month: "long",
    day: "numeric",
    weekday: "short",
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
    timeZone,
  }).format(new Date(isoDateTime));
}
