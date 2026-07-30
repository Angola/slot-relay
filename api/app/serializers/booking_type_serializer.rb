# frozen_string_literal: true

# 予約メニューの JSON 表現。キーは camelCase（外部サイトの JS から使うため）。
#
# 公開 API には画面表示に必要な項目だけを返す。前後バッファ・登録先カレンダー ID など
# 内部設定は公開ペイロードに含めない。
module BookingTypeSerializer
  module_function

  def public_payload(booking_type)
    {
      slug: booking_type.slug,
      name: booking_type.name,
      description: booking_type.description,
      durationMinutes: booking_type.duration_minutes,
      timeZone: booking_type.time_zone,
      minimumNoticeMinutes: booking_type.minimum_notice_minutes,
      bookingWindowDays: booking_type.booking_window_days
    }
  end

  def admin_payload(booking_type)
    public_payload(booking_type).merge(
      id: booking_type.id,
      status: booking_type.status,
      bufferBeforeMinutes: booking_type.buffer_before_minutes,
      bufferAfterMinutes: booking_type.buffer_after_minutes,
      googleBookingCalendarId: booking_type.google_booking_calendar_id,
      googleBusyCalendarIds: booking_type.google_busy_calendar_ids,
      allowedOrigins: booking_type.origins.map(&:origin).sort,
      weeklyAvailability: weekly_availability_payload(booking_type),
      availabilityOverrides: availability_overrides_payload(booking_type),
      createdAt: booking_type.created_at.iso8601,
      updatedAt: booking_type.updated_at.iso8601
    )
  end

  def weekly_availability_payload(booking_type)
    booking_type.weekly_availabilities
                .sort_by { |wa| [wa.day_of_week, wa.start_time_minutes.to_i] }
                .map do |wa|
      { dayOfWeek: wa.day_of_week, startTime: wa.start_time_hhmm, endTime: wa.end_time_hhmm }
    end
  end

  def availability_overrides_payload(booking_type)
    booking_type.availability_overrides.sort_by(&:date).map do |override|
      {
        date: override.date.iso8601,
        isAvailable: override.is_available,
        startTime: override.start_time_hhmm,
        endTime: override.end_time_hhmm
      }
    end
  end
end
