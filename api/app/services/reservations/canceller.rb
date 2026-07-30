# frozen_string_literal: true

module Reservations
  # 予約のキャンセル。DB を cancelled にし、Google カレンダーの予定も削除する。
  #
  # Google 側の削除に失敗しても DB のキャンセルは確定させる（利用者から見て
  # 「キャンセルできない」状態を作らない）。取り残された予定は管理者メールで通知する。
  class Canceller
    def initialize(reservation:, calendar_client: SlotRelay.calendar_client, now: Time.current)
      @reservation = reservation
      @calendar_client = calendar_client
      @now = now
    end

    # @return [ServiceResult] 成功時 value は Reservation
    def call
      return ServiceResult.success(reservation) if reservation.cancelled?

      unless reservation.cancellable?
        return ServiceResult.failure(
          :not_cancellable, "この予約はキャンセルできません（状態: #{reservation.status}）。"
        )
      end

      delete_google_event
      reservation.update!(status: "cancelled", cancelled_at: now, expires_at: nil)
      deliver_notifications

      ServiceResult.success(reservation)
    end

    private

    attr_reader :reservation, :calendar_client, :now

    def delete_google_event
      return if reservation.google_event_id.blank?

      calendar_client.delete_event(
        calendar_id: reservation.booking_type.booking_calendar_id,
        event_id: reservation.google_event_id
      )
    rescue GoogleCalendar::Client::Error => e
      Rails.logger.error("[slot-relay] Google 予定の削除に失敗しました: #{e.message}")
      safe_deliver { AdminMailer.calendar_error(reservation, e.message).deliver_now }
    end

    def deliver_notifications
      safe_deliver { GuestMailer.reservation_cancelled(reservation).deliver_now }
      safe_deliver { AdminMailer.reservation_cancelled(reservation).deliver_now }
    end

    def safe_deliver
      yield
    rescue StandardError => e
      Rails.logger.error("[slot-relay] メール送信に失敗しました: #{e.class}: #{e.message}")
    end
  end
end
