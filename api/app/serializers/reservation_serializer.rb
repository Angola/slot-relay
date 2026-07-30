# frozen_string_literal: true

# 予約の JSON 表現。
#
# cancel_token_hash はどのペイロードにも含めない。キャンセル URL は
# トークンが手元にある瞬間（予約作成の応答）だけ返す。
module ReservationSerializer
  module_function

  def public_payload(reservation, include_cancel_url: false)
    tz = reservation.booking_type.tz

    payload = {
      reservationId: reservation.public_id,
      status: reservation.status,
      startAt: reservation.start_at.in_time_zone(tz).iso8601,
      endAt: reservation.end_at.in_time_zone(tz).iso8601,
      bookingType: {
        slug: reservation.booking_type.slug,
        name: reservation.booking_type.name,
        durationMinutes: reservation.booking_type.duration_minutes,
        timeZone: reservation.booking_type.time_zone
      },
      guest: {
        name: reservation.guest_name,
        email: reservation.guest_email,
        company: reservation.guest_company,
        phone: reservation.guest_phone
      },
      answers: reservation.answers,
      cancelledAt: reservation.cancelled_at&.in_time_zone(tz)&.iso8601
    }

    if include_cancel_url && reservation.cancel_token.present?
      payload[:cancelUrl] = SlotRelay.config.cancel_url_for(reservation.public_id, reservation.cancel_token)
    end

    payload
  end

  def admin_payload(reservation)
    tz = reservation.booking_type.tz

    public_payload(reservation).merge(
      id: reservation.id,
      bookingTypeId: reservation.booking_type_id,
      googleEventId: reservation.google_event_id,
      expiresAt: reservation.expires_at&.in_time_zone(tz)&.iso8601,
      createdAt: reservation.created_at.in_time_zone(tz).iso8601,
      updatedAt: reservation.updated_at.in_time_zone(tz).iso8601
    )
  end
end
