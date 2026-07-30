# frozen_string_literal: true

# 管理者（自分）向け通知メール。ADMIN_NOTIFICATION_EMAIL が未設定なら送らない。
class AdminMailer < ApplicationMailer
  def reservation_created(reservation)
    @reservation = reservation
    @booking_type = reservation.booking_type
    @period = format_period(reservation)

    admin_mail(subject: "[新規予約] #{@booking_type.name} / #{reservation.guest_name}")
  end

  def reservation_cancelled(reservation)
    @reservation = reservation
    @booking_type = reservation.booking_type
    @period = format_period(reservation)

    admin_mail(subject: "[予約キャンセル] #{@booking_type.name} / #{reservation.guest_name}")
  end

  def calendar_error(reservation, error_message)
    @reservation = reservation
    @booking_type = reservation.booking_type
    @period = format_period(reservation)
    @error_message = error_message

    admin_mail(subject: "[要対応] Google カレンダー連携エラー / #{reservation.public_id}")
  end

  private

  def admin_mail(subject:)
    recipient = SlotRelay.config.admin_notification_email
    return NullMail.new if recipient.blank?

    mail(to: recipient, subject: subject)
  end

  # ADMIN_NOTIFICATION_EMAIL 未設定時に deliver_now を呼んでも落ちないようにする。
  class NullMail
    def deliver_now = self
    def deliver_later = self
    def message = ActionMailer::Base::NullMail.new
  end
end
