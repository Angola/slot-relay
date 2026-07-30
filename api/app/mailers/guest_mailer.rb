# frozen_string_literal: true

# 予約者向けメール。件名・本文に個人情報は載るが、ログには出さない（DESIGN §9）。
class GuestMailer < ApplicationMailer
  def reservation_confirmed(reservation)
    @reservation = reservation
    @booking_type = reservation.booking_type
    @period = format_period(reservation)
    @cancel_url = cancel_url_for(reservation)

    mail(to: reservation.guest_email, subject: "【#{@booking_type.name}】ご予約を承りました")
  end

  def reservation_cancelled(reservation)
    @reservation = reservation
    @booking_type = reservation.booking_type
    @period = format_period(reservation)

    mail(to: reservation.guest_email, subject: "【#{@booking_type.name}】ご予約をキャンセルしました")
  end

  def reservation_rescheduled(reservation, previous_start_at)
    @reservation = reservation
    @booking_type = reservation.booking_type
    @period = format_period(reservation)
    @previous_start_at = previous_start_at&.in_time_zone(@booking_type.tz)
    @cancel_url = cancel_url_for(reservation)

    mail(to: reservation.guest_email, subject: "【#{@booking_type.name}】ご予約日時を変更しました")
  end

  private

  # キャンセル URL には生のトークンが必要。発行直後（メモリ上にトークンがある）以外は
  # ハッシュしか残っていないため URL を出さない。
  def cancel_url_for(reservation)
    return nil if reservation.cancel_token.blank?

    SlotRelay.config.cancel_url_for(reservation.public_id, reservation.cancel_token)
  end
end
