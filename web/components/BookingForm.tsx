"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import {
  BookingApiError,
  createReservation,
  fetchAvailability,
  fetchBookingType,
  newIdempotencyKey,
  type Availability,
  type BookingType,
  type Reservation,
} from "@/lib/bookingApi";
import { addDays, formatDateLabel, formatDateTimeLabel, formatTimeLabel, toDateParam } from "@/lib/datetime";
import { TurnstileWidget } from "./TurnstileWidget";

const RANGE_DAYS = 14;

type Step = "picking" | "filling" | "done";

/**
 * 予約フォームの参照実装。
 *
 *   日付・時間を選ぶ → 氏名などを入力 → Turnstile → 予約 POST → 完了
 *
 * Idempotency-Key は「入力を終えて送信ボタンを押せる状態になった 1 回の予約」に
 * 対して 1 つ発行する。送信失敗後の再送では同じキーを使い、二重予約を防ぐ。
 */
export function BookingForm({ slug }: { slug: string }) {
  const [bookingType, setBookingType] = useState<BookingType | null>(null);
  const [availability, setAvailability] = useState<Availability | null>(null);
  const [rangeStart, setRangeStart] = useState(() => new Date());
  const [selectedDate, setSelectedDate] = useState<string | null>(null);
  const [selectedSlot, setSelectedSlot] = useState<string | null>(null);
  const [step, setStep] = useState<Step>("picking");
  const [guest, setGuest] = useState({ name: "", email: "", company: "", phone: "" });
  const [consultation, setConsultation] = useState("");
  const [turnstileToken, setTurnstileToken] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [reservation, setReservation] = useState<Reservation | null>(null);

  const idempotencyKey = useRef(newIdempotencyKey());
  const timeZone = availability?.timeZone ?? bookingType?.timeZone ?? "Asia/Tokyo";

  const loadAvailability = useCallback(
    async (start: Date) => {
      setError(null);
      try {
        const from = toDateParam(start);
        const to = toDateParam(addDays(start, RANGE_DAYS - 1));
        setAvailability(await fetchAvailability(slug, from, to));
      } catch (cause) {
        setError(cause instanceof Error ? cause.message : "空き枠を取得できませんでした。");
      }
    },
    [slug],
  );

  useEffect(() => {
    fetchBookingType(slug)
      .then(setBookingType)
      .catch((cause: unknown) => {
        setError(cause instanceof Error ? cause.message : "予約メニューを取得できませんでした。");
      });
  }, [slug]);

  useEffect(() => {
    void loadAvailability(rangeStart);
  }, [loadAvailability, rangeStart]);

  const bookableDays = useMemo(
    () => (availability?.days ?? []).filter((day) => day.slots.length > 0),
    [availability],
  );

  const slotsOfSelectedDate = useMemo(
    () => bookableDays.find((day) => day.date === selectedDate)?.slots ?? [],
    [bookableDays, selectedDate],
  );

  async function submit(event: React.FormEvent) {
    event.preventDefault();
    if (!selectedSlot || submitting) return;

    setSubmitting(true);
    setError(null);

    try {
      const created = await createReservation(
        slug,
        {
          startAt: selectedSlot,
          guest: {
            name: guest.name,
            email: guest.email,
            company: guest.company || undefined,
            phone: guest.phone || undefined,
          },
          answers: consultation ? { 相談内容: consultation } : {},
          turnstileToken: turnstileToken || undefined,
        },
        idempotencyKey.current,
      );

      setReservation(created);
      setStep("done");
    } catch (cause) {
      if (cause instanceof BookingApiError && cause.isSlotUnavailable) {
        // 枠が埋まったので、選び直しへ戻す。次の予約は新しいキーで送る。
        idempotencyKey.current = newIdempotencyKey();
        setSelectedSlot(null);
        setStep("picking");
        await loadAvailability(rangeStart);
        setError(cause.message);
      } else if (cause instanceof BookingApiError) {
        setError([cause.message, ...(cause.details ?? [])].join(" / "));
      } else {
        setError("予約を登録できませんでした。時間をおいて再度お試しください。");
      }
    } finally {
      setSubmitting(false);
    }
  }

  if (step === "done" && reservation) {
    return (
      <section className="card" aria-labelledby="done-heading">
        <h2 id="done-heading">ご予約を承りました</h2>
        <dl className="summary">
          <dt>予約番号</dt>
          <dd>{reservation.reservationId}</dd>
          <dt>日時</dt>
          <dd>{formatDateTimeLabel(reservation.startAt, reservation.bookingType.timeZone)}</dd>
          <dt>メニュー</dt>
          <dd>{reservation.bookingType.name}</dd>
        </dl>
        <p>確認メールを {reservation.guest.email} へ送信しました。</p>
        {reservation.cancelUrl && (
          <p className="muted">
            キャンセルは <a href={reservation.cancelUrl}>こちらの URL</a> から行えます（メールにも記載しています）。
          </p>
        )}
      </section>
    );
  }

  return (
    <div className="booking">
      <header className="card">
        <h1>{bookingType?.name ?? "予約"}</h1>
        {bookingType?.description && <p>{bookingType.description}</p>}
        {bookingType && (
          <p className="muted">
            所要時間 {bookingType.durationMinutes} 分 / {bookingType.timeZone}
          </p>
        )}
      </header>

      {error && (
        <p className="error" role="alert">
          {error}
        </p>
      )}

      <section className="card" aria-labelledby="slot-heading">
        <h2 id="slot-heading">1. 日時を選ぶ</h2>

        <div className="range-nav">
          <button
            type="button"
            onClick={() => setRangeStart(addDays(rangeStart, -RANGE_DAYS))}
            disabled={toDateParam(rangeStart) <= toDateParam(new Date())}
          >
            前の 2 週間
          </button>
          <button type="button" onClick={() => setRangeStart(addDays(rangeStart, RANGE_DAYS))}>
            次の 2 週間
          </button>
        </div>

        {availability === null ? (
          <p className="muted">空き枠を読み込んでいます…</p>
        ) : bookableDays.length === 0 ? (
          <p className="muted">この期間に予約できる枠がありません。別の期間をお試しください。</p>
        ) : (
          <ul className="day-list">
            {bookableDays.map((day) => (
              <li key={day.date}>
                <button
                  type="button"
                  aria-pressed={selectedDate === day.date}
                  className={selectedDate === day.date ? "chip selected" : "chip"}
                  onClick={() => {
                    setSelectedDate(day.date);
                    setSelectedSlot(null);
                  }}
                >
                  {formatDateLabel(day.date, timeZone)}
                </button>
              </li>
            ))}
          </ul>
        )}

        {selectedDate && (
          <ul className="slot-list" aria-label="時間の選択">
            {slotsOfSelectedDate.map((slot) => (
              <li key={slot.startAt}>
                <button
                  type="button"
                  aria-pressed={selectedSlot === slot.startAt}
                  className={selectedSlot === slot.startAt ? "chip selected" : "chip"}
                  onClick={() => {
                    setSelectedSlot(slot.startAt);
                    setStep("filling");
                  }}
                >
                  {formatTimeLabel(slot.startAt, timeZone)}
                </button>
              </li>
            ))}
          </ul>
        )}
      </section>

      <section className="card" aria-labelledby="guest-heading">
        <h2 id="guest-heading">2. お客様情報を入力する</h2>

        {selectedSlot ? (
          <p className="selected-slot">選択中: {formatDateTimeLabel(selectedSlot, timeZone)}</p>
        ) : (
          <p className="muted">先に日時を選んでください。</p>
        )}

        <form onSubmit={submit}>
          <label>
            お名前（必須）
            <input
              type="text"
              required
              value={guest.name}
              onChange={(event) => setGuest({ ...guest, name: event.target.value })}
            />
          </label>
          <label>
            メールアドレス（必須）
            <input
              type="email"
              required
              value={guest.email}
              onChange={(event) => setGuest({ ...guest, email: event.target.value })}
            />
          </label>
          <label>
            会社名
            <input
              type="text"
              value={guest.company}
              onChange={(event) => setGuest({ ...guest, company: event.target.value })}
            />
          </label>
          <label>
            電話番号
            <input
              type="tel"
              value={guest.phone}
              onChange={(event) => setGuest({ ...guest, phone: event.target.value })}
            />
          </label>
          <label>
            ご相談内容
            <textarea rows={4} value={consultation} onChange={(event) => setConsultation(event.target.value)} />
          </label>

          <TurnstileWidget onToken={setTurnstileToken} />

          <button type="submit" className="primary" disabled={!selectedSlot || submitting}>
            {submitting ? "送信中…" : "この日時で予約する"}
          </button>
        </form>
      </section>
    </div>
  );
}
