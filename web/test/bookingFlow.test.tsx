import { beforeEach, describe, expect, it, vi } from "vitest";
import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { BookingForm } from "@/components/BookingForm";
import { CancelPanel } from "@/components/CancelPanel";

/**
 * 画面遷移のテスト。
 *
 *   日付選択 → 時間選択 → 入力 → 予約 POST → 完了画面
 *   ＋ 枠が埋まっていた場合に選び直しへ戻ること
 *   ＋ キャンセル画面
 */

const BOOKING_TYPE = {
  slug: "genba-tsunagu-consultation",
  name: "無料相談",
  description: "業務自動化の無料相談",
  durationMinutes: 60,
  timeZone: "Asia/Tokyo",
  minimumNoticeMinutes: 1440,
  bookingWindowDays: 30,
};

const AVAILABILITY = {
  timeZone: "Asia/Tokyo",
  durationMinutes: 60,
  days: [
    { date: "2026-08-01", slots: [] },
    {
      date: "2026-08-03",
      slots: [
        { startAt: "2026-08-03T10:00:00+09:00", endAt: "2026-08-03T11:00:00+09:00" },
        { startAt: "2026-08-03T11:00:00+09:00", endAt: "2026-08-03T12:00:00+09:00" },
      ],
    },
  ],
};

const RESERVATION = {
  reservationId: "res_abc123",
  status: "confirmed" as const,
  startAt: "2026-08-03T10:00:00+09:00",
  endAt: "2026-08-03T11:00:00+09:00",
  bookingType: { slug: BOOKING_TYPE.slug, name: "無料相談", durationMinutes: 60, timeZone: "Asia/Tokyo" },
  guest: { name: "山田太郎", email: "taro@example.com", company: "株式会社サンプル", phone: null },
  answers: { 相談内容: "日報業務を自動化したい" },
  cancelledAt: null,
  cancelUrl: "https://booking-api.example.com/c/res_abc123/token-xyz",
};

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

/** URL に応じて応答を返す fetch のスタブ */
function stubApi(handlers: {
  bookingType?: () => Response;
  availability?: () => Response;
  createReservation?: () => Response;
  reservation?: () => Response;
  cancel?: () => Response;
}) {
  const fetchMock = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = String(input);

    if (url.includes("/availability")) return (handlers.availability ?? (() => jsonResponse(AVAILABILITY)))();
    if (url.includes("/reservations") && init?.method === "POST" && url.includes("/booking-types/")) {
      return (handlers.createReservation ?? (() => jsonResponse(RESERVATION, 201)))();
    }
    if (url.includes("/cancel")) return (handlers.cancel ?? (() => jsonResponse({ ...RESERVATION, status: "cancelled" })))();
    if (url.includes("/v1/public/reservations/")) return (handlers.reservation ?? (() => jsonResponse(RESERVATION)))();
    if (url.includes("/booking-types/")) return (handlers.bookingType ?? (() => jsonResponse(BOOKING_TYPE)))();

    throw new Error(`予期しないリクエスト: ${url}`);
  });

  vi.stubGlobal("fetch", fetchMock);
  return fetchMock;
}

async function fillGuestForm(user: ReturnType<typeof userEvent.setup>) {
  await user.type(screen.getByLabelText("お名前（必須）"), "山田太郎");
  await user.type(screen.getByLabelText("メールアドレス（必須）"), "taro@example.com");
  await user.type(screen.getByLabelText("会社名"), "株式会社サンプル");
  await user.type(screen.getByLabelText("ご相談内容"), "日報業務を自動化したい");
}

describe("予約フォームの画面遷移", () => {
  beforeEach(() => {
    vi.useRealTimers();
  });

  it("日付選択 → 時間選択 → 入力 → 予約 → 完了画面まで進む", async () => {
    const fetchMock = stubApi({});
    const user = userEvent.setup();

    render(<BookingForm slug={BOOKING_TYPE.slug} />);

    // メニュー情報と空き枠が読み込まれる
    expect(await screen.findByRole("heading", { level: 1, name: "無料相談" })).toBeDefined();
    expect(await screen.findByText("所要時間 60 分 / Asia/Tokyo")).toBeDefined();

    // 枠が 0 件の日はボタンにしない
    expect(screen.queryByRole("button", { name: /8月1日/ })).toBeNull();

    // 日付を選ぶと時間が並ぶ
    await user.click(await screen.findByRole("button", { name: /8月3日/ }));
    const slotList = await screen.findByRole("list", { name: "時間の選択" });
    expect(slotList.querySelectorAll("button")).toHaveLength(2);

    // 時間を選ぶと選択中として表示される
    await user.click(screen.getByRole("button", { name: "10:00" }));
    expect(screen.getByText(/選択中: 2026年8月3日\(月\) 10:00/)).toBeDefined();

    // 入力して送信
    await fillGuestForm(user);
    await user.click(screen.getByRole("button", { name: "この日時で予約する" }));

    // 完了画面
    expect(await screen.findByRole("heading", { name: "ご予約を承りました" })).toBeDefined();
    expect(screen.getByText("res_abc123")).toBeDefined();
    expect(screen.getByText(/確認メールを taro@example.com へ送信しました/)).toBeDefined();
    expect(screen.getByRole("link", { name: "こちらの URL" }).getAttribute("href")).toBe(RESERVATION.cancelUrl);

    // 予約 POST の中身
    const postCall = fetchMock.mock.calls.find(([, init]) => init?.method === "POST");
    const body = JSON.parse(String(postCall?.[1]?.body));
    expect(body).toMatchObject({
      startAt: "2026-08-03T10:00:00+09:00",
      guest: { name: "山田太郎", email: "taro@example.com", company: "株式会社サンプル" },
      answers: { 相談内容: "日報業務を自動化したい" },
    });
  });

  it("枠が埋まっていたら選び直しに戻し、空き枠を再取得する", async () => {
    const fetchMock = stubApi({
      createReservation: () =>
        jsonResponse({ code: "SLOT_UNAVAILABLE", message: "選択された時間は利用できなくなりました。" }, 409),
    });
    const user = userEvent.setup();

    render(<BookingForm slug={BOOKING_TYPE.slug} />);

    await user.click(await screen.findByRole("button", { name: /8月3日/ }));
    await user.click(await screen.findByRole("button", { name: "10:00" }));
    await fillGuestForm(user);

    const availabilityCallsBefore = fetchMock.mock.calls.filter(([url]) =>
      String(url).includes("/availability"),
    ).length;

    await user.click(screen.getByRole("button", { name: "この日時で予約する" }));

    expect(await screen.findByRole("alert")).toHaveProperty(
      "textContent",
      "選択された時間は利用できなくなりました。",
    );
    // 完了画面には進まない
    expect(screen.queryByRole("heading", { name: "ご予約を承りました" })).toBeNull();
    // 選択が解除され、送信ボタンが押せなくなる
    expect(screen.getByRole("button", { name: "この日時で予約する" })).toHaveProperty("disabled", true);
    // 空き枠を取り直している
    await waitFor(() => {
      const after = fetchMock.mock.calls.filter(([url]) => String(url).includes("/availability")).length;
      expect(after).toBeGreaterThan(availabilityCallsBefore);
    });
  });

  it("入力エラー（422）は details まで表示する", async () => {
    stubApi({
      createReservation: () =>
        jsonResponse(
          { code: "VALIDATION_FAILED", message: "入力内容に誤りがあります。", details: ["Guest email は不正な値です"] },
          422,
        ),
    });
    const user = userEvent.setup();

    render(<BookingForm slug={BOOKING_TYPE.slug} />);

    await user.click(await screen.findByRole("button", { name: /8月3日/ }));
    await user.click(await screen.findByRole("button", { name: "10:00" }));
    await fillGuestForm(user);
    await user.click(screen.getByRole("button", { name: "この日時で予約する" }));

    const alert = await screen.findByRole("alert");
    expect(alert.textContent).toContain("入力内容に誤りがあります。");
    expect(alert.textContent).toContain("Guest email は不正な値です");
  });

  it("空き枠が取れないときはエラーを見せる", async () => {
    stubApi({
      availability: () =>
        jsonResponse({ code: "CALENDAR_ERROR", message: "空き枠を取得できませんでした。" }, 502),
    });

    render(<BookingForm slug={BOOKING_TYPE.slug} />);

    expect(await screen.findByRole("alert")).toHaveProperty("textContent", "空き枠を取得できませんでした。");
  });

  it("予約できる枠が 1 件も無ければ案内を出す", async () => {
    stubApi({
      availability: () =>
        jsonResponse({ timeZone: "Asia/Tokyo", durationMinutes: 60, days: [{ date: "2026-08-01", slots: [] }] }),
    });

    render(<BookingForm slug={BOOKING_TYPE.slug} />);

    expect(
      await screen.findByText("この期間に予約できる枠がありません。別の期間をお試しください。"),
    ).toBeDefined();
  });
});

describe("キャンセル画面", () => {
  it("予約内容を表示してキャンセルできる", async () => {
    stubApi({});
    const user = userEvent.setup();

    render(<CancelPanel token="token-xyz" />);

    expect(await screen.findByRole("heading", { name: "ご予約のキャンセル" })).toBeDefined();
    expect(screen.getByText("res_abc123")).toBeDefined();
    expect(screen.getByText(/2026年8月3日\(月\) 10:00/)).toBeDefined();

    await user.click(screen.getByRole("button", { name: "この予約をキャンセルする" }));

    expect(await screen.findByRole("heading", { name: "キャンセル済みです" })).toBeDefined();
    expect(screen.queryByRole("button", { name: "この予約をキャンセルする" })).toBeNull();
  });

  it("トークンが不正なら見つからない旨を表示する", async () => {
    stubApi({
      reservation: () => jsonResponse({ code: "NOT_FOUND", message: "リソースが見つかりません。" }, 404),
    });

    render(<CancelPanel token="wrong" />);

    expect(await screen.findByRole("heading", { name: "予約が見つかりません" })).toBeDefined();
  });

  it("すでにキャンセル済みならボタンを出さない", async () => {
    stubApi({ reservation: () => jsonResponse({ ...RESERVATION, status: "cancelled" }) });

    render(<CancelPanel token="token-xyz" />);

    expect(await screen.findByRole("heading", { name: "キャンセル済みです" })).toBeDefined();
    expect(screen.queryByRole("button")).toBeNull();
  });
});
