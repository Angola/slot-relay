/**
 * 予約 API のクライアント。
 *
 * サイト側が使うのは公開 API の 2 本だけで予約画面が成立する（docs/DESIGN.md §12）。
 *   GET  /v1/public/booking-types/:slug/availability
 *   POST /v1/public/booking-types/:slug/reservations
 *
 * 照会・キャンセルはメールのトークンを持っている人だけが使う。
 */
import { bookingApiUrl } from "./config";

export type Slot = { startAt: string; endAt: string };
export type AvailabilityDay = { date: string; slots: Slot[] };

export type Availability = {
  timeZone: string;
  durationMinutes: number;
  days: AvailabilityDay[];
};

export type BookingType = {
  slug: string;
  name: string;
  description: string | null;
  durationMinutes: number;
  timeZone: string;
  minimumNoticeMinutes: number;
  bookingWindowDays: number;
};

export type Reservation = {
  reservationId: string;
  status: "pending" | "confirmed" | "cancelled" | "failed";
  startAt: string;
  endAt: string;
  bookingType: { slug: string; name: string; durationMinutes: number; timeZone: string };
  guest: { name: string; email: string; company: string | null; phone: string | null };
  answers: Record<string, string>;
  cancelledAt: string | null;
  cancelUrl?: string;
};

export type Guest = {
  name: string;
  email: string;
  company?: string;
  phone?: string;
};

export type CreateReservationInput = {
  startAt: string;
  guest: Guest;
  answers?: Record<string, string>;
  turnstileToken?: string;
};

/** API がエラー応答（{ code, message }）を返したときに投げる */
export class BookingApiError extends Error {
  readonly code: string;
  readonly status: number;
  readonly details?: string[];

  constructor(status: number, code: string, message: string, details?: string[]) {
    super(message);
    this.name = "BookingApiError";
    this.status = status;
    this.code = code;
    this.details = details;
  }

  /** 枠が埋まった場合は「空き枠を再取得して選び直す」導線に戻したい */
  get isSlotUnavailable(): boolean {
    return this.code === "SLOT_UNAVAILABLE";
  }
}

async function request<T>(path: string, init?: RequestInit): Promise<T> {
  const response = await fetch(`${bookingApiUrl}${path}`, {
    ...init,
    headers: { Accept: "application/json", ...(init?.headers ?? {}) },
  });

  const text = await response.text();
  const body = text.length > 0 ? JSON.parse(text) : {};

  if (!response.ok) {
    throw new BookingApiError(
      response.status,
      typeof body.code === "string" ? body.code : "UNKNOWN_ERROR",
      typeof body.message === "string" ? body.message : "予約 API でエラーが発生しました。",
      Array.isArray(body.details) ? body.details : undefined,
    );
  }

  return body as T;
}

export function fetchBookingType(slug: string): Promise<BookingType> {
  return request<BookingType>(`/v1/public/booking-types/${encodeURIComponent(slug)}`);
}

export function fetchAvailability(slug: string, from: string, to: string): Promise<Availability> {
  const query = new URLSearchParams({ from, to });
  return request<Availability>(
    `/v1/public/booking-types/${encodeURIComponent(slug)}/availability?${query}`,
  );
}

export function createReservation(
  slug: string,
  input: CreateReservationInput,
  idempotencyKey: string,
): Promise<Reservation> {
  return request<Reservation>(
    `/v1/public/booking-types/${encodeURIComponent(slug)}/reservations`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        // 再送で二重予約にならないよう、予約 1 回につき 1 つのキーを送る
        "Idempotency-Key": idempotencyKey,
      },
      body: JSON.stringify(input),
    },
  );
}

export function fetchReservation(token: string): Promise<Reservation> {
  return request<Reservation>(`/v1/public/reservations/${encodeURIComponent(token)}`);
}

export function cancelReservation(token: string): Promise<Reservation> {
  return request<Reservation>(`/v1/public/reservations/${encodeURIComponent(token)}/cancel`, {
    method: "POST",
  });
}

/** Idempotency-Key。crypto.randomUUID が無い環境（古い Safari 等）にも備える */
export function newIdempotencyKey(): string {
  if (typeof crypto !== "undefined" && typeof crypto.randomUUID === "function") {
    return crypto.randomUUID();
  }

  return `${Date.now().toString(16)}-${Math.random().toString(16).slice(2)}`;
}
