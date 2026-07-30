# frozen_string_literal: true

# 空き枠の JSON 表現。時刻は予約メニューのタイムゾーンのオフセット付き RFC 3339
# （例: 2026-08-03T10:00:00+09:00）で返す。
module AvailabilitySerializer
  module_function

  def payload(booking_type:, days:)
    tz = booking_type.tz

    {
      timeZone: booking_type.time_zone,
      durationMinutes: booking_type.duration_minutes,
      days: days.map do |day|
        {
          date: day.date.iso8601,
          slots: day.slots.map do |slot|
            {
              startAt: slot.start_at.in_time_zone(tz).iso8601,
              endAt: slot.end_at.in_time_zone(tz).iso8601
            }
          end
        }
      end
    }
  end
end
