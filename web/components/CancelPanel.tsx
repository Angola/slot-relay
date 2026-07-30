"use client";

import { useEffect, useState } from "react";
import { cancelReservation, fetchReservation, type Reservation } from "@/lib/bookingApi";
import { formatDateTimeLabel } from "@/lib/datetime";

/**
 * キャンセル画面。確認メールの URL（/c/:publicId/:token）から開かれる。
 * 認可はトークンだけで行うため、予約番号を知っているだけでは他人の予約を触れない。
 */
export function CancelPanel({ token }: { token: string }) {
  const [reservation, setReservation] = useState<Reservation | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [working, setWorking] = useState(false);

  useEffect(() => {
    fetchReservation(token)
      .then(setReservation)
      .catch((cause: unknown) => {
        setError(cause instanceof Error ? cause.message : "予約が見つかりませんでした。");
      });
  }, [token]);

  async function cancel() {
    setWorking(true);
    setError(null);
    try {
      setReservation(await cancelReservation(token));
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "キャンセルできませんでした。");
    } finally {
      setWorking(false);
    }
  }

  if (error && !reservation) {
    return (
      <section className="card">
        <h1>予約が見つかりません</h1>
        <p role="alert">{error}</p>
        <p className="muted">URL が古い、または一度使われている可能性があります。</p>
      </section>
    );
  }

  if (!reservation) {
    return (
      <section className="card">
        <p className="muted">予約を読み込んでいます…</p>
      </section>
    );
  }

  const cancelled = reservation.status === "cancelled";

  return (
    <section className="card">
      <h1>{cancelled ? "キャンセル済みです" : "ご予約のキャンセル"}</h1>

      <dl className="summary">
        <dt>予約番号</dt>
        <dd>{reservation.reservationId}</dd>
        <dt>メニュー</dt>
        <dd>{reservation.bookingType.name}</dd>
        <dt>日時</dt>
        <dd>{formatDateTimeLabel(reservation.startAt, reservation.bookingType.timeZone)}</dd>
        <dt>お名前</dt>
        <dd>{reservation.guest.name}</dd>
      </dl>

      {error && (
        <p className="error" role="alert">
          {error}
        </p>
      )}

      {cancelled ? (
        <p>この予約はキャンセルされています。あらためてご予約いただけます。</p>
      ) : (
        <button type="button" className="primary" onClick={cancel} disabled={working}>
          {working ? "処理中…" : "この予約をキャンセルする"}
        </button>
      )}
    </section>
  );
}
