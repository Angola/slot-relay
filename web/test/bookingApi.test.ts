import { beforeEach, describe, expect, it, vi } from "vitest";
import {
  BookingApiError,
  cancelReservation,
  createReservation,
  fetchAvailability,
  fetchReservation,
  newIdempotencyKey,
} from "@/lib/bookingApi";

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

describe("bookingApi", () => {
  beforeEach(() => {
    vi.stubGlobal("fetch", vi.fn());
  });

  it("空き枠を from / to つきで取得する", async () => {
    const availability = { timeZone: "Asia/Tokyo", durationMinutes: 60, days: [] };
    vi.mocked(fetch).mockResolvedValue(jsonResponse(availability));

    const result = await fetchAvailability("genba-tsunagu-consultation", "2026-08-01", "2026-08-07");

    expect(result).toEqual(availability);
    const [url] = vi.mocked(fetch).mock.calls[0];
    expect(String(url)).toContain(
      "/v1/public/booking-types/genba-tsunagu-consultation/availability?from=2026-08-01&to=2026-08-07",
    );
  });

  it("予約 POST に Idempotency-Key を必ず載せる", async () => {
    vi.mocked(fetch).mockResolvedValue(jsonResponse({ reservationId: "res_x" }, 201));

    await createReservation(
      "genba-tsunagu-consultation",
      { startAt: "2026-08-03T10:00:00+09:00", guest: { name: "山田太郎", email: "taro@example.com" } },
      "key-1",
    );

    const [, init] = vi.mocked(fetch).mock.calls[0];
    const headers = init?.headers as Record<string, string>;

    expect(init?.method).toBe("POST");
    expect(headers["Idempotency-Key"]).toBe("key-1");
    expect(JSON.parse(String(init?.body))).toMatchObject({ startAt: "2026-08-03T10:00:00+09:00" });
  });

  it("409 SLOT_UNAVAILABLE を BookingApiError として投げる", async () => {
    vi.mocked(fetch).mockResolvedValue(
      jsonResponse({ code: "SLOT_UNAVAILABLE", message: "選択された時間は利用できなくなりました。" }, 409),
    );

    const error = await createReservation(
      "slug",
      { startAt: "2026-08-03T10:00:00+09:00", guest: { name: "a", email: "a@example.com" } },
      "key-1",
    ).catch((cause: unknown) => cause);

    expect(error).toBeInstanceOf(BookingApiError);
    const apiError = error as BookingApiError;
    expect(apiError.isSlotUnavailable).toBe(true);
    expect(apiError.status).toBe(409);
    expect(apiError.message).toBe("選択された時間は利用できなくなりました。");
  });

  it("422 の details をエラーに載せる", async () => {
    vi.mocked(fetch).mockResolvedValue(
      jsonResponse({ code: "VALIDATION_FAILED", message: "入力内容に誤りがあります。", details: ["メールが不正"] }, 422),
    );

    const error = (await fetchReservation("token").catch((cause: unknown) => cause)) as BookingApiError;

    expect(error.details).toEqual(["メールが不正"]);
    expect(error.isSlotUnavailable).toBe(false);
  });

  it("本文が空の応答でも落ちない", async () => {
    vi.mocked(fetch).mockResolvedValue(new Response("", { status: 200 }));

    await expect(cancelReservation("token")).resolves.toEqual({});
  });

  it("トークンは URL エスケープする", async () => {
    vi.mocked(fetch).mockResolvedValue(jsonResponse({}));

    await fetchReservation("a/b?c");

    expect(String(vi.mocked(fetch).mock.calls[0][0])).toContain("/v1/public/reservations/a%2Fb%3Fc");
  });

  it("Idempotency-Key は毎回異なる", () => {
    expect(newIdempotencyKey()).not.toBe(newIdempotencyKey());
  });
});
