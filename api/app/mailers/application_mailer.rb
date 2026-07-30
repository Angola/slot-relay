# frozen_string_literal: true

class ApplicationMailer < ActionMailer::Base
  default from: -> { SlotRelay.config.mail_from }
  layout "mailer"

  private

  # 予約メニューのタイムゾーンで「2026年8月3日(月) 10:00〜11:00」の形に整える。
  def format_period(reservation)
    tz = reservation.booking_type.tz
    start_at = reservation.start_at.in_time_zone(tz)
    end_at = reservation.end_at.in_time_zone(tz)

    "#{I18n.l(start_at, format: :reservation)}〜#{end_at.strftime("%H:%M")}"
  end
end
