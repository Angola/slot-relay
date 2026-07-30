# frozen_string_literal: true

module Reservations
  # 予約の日時変更（管理 API 専用）。
  #
  # 手順は「先に DB の枠を押さえてから Google を触る」。順序を逆にすると、
  # DB の排他制約を通らない時間帯に Google 予定だけができてしまう。
  #
  #   1. DB の start_at / end_at を更新（排他制約で重なりを弾く）
  #   2. Google FreeBusy と受付時間で新しい枠が妥当か再確認
  #   3. 新しい Google 予定を作成 → 古い予定を削除
  #
  # 2 で不可・3 で失敗した場合は元の日時へ戻す。
  class Rescheduler
    def initialize(reservation:, start_at:, calendar_client: SlotRelay.calendar_client, now: Time.current)
      @reservation = reservation
      @requested_start_at = start_at
      @calendar_client = calendar_client
      @now = now
    end

    # @return [ServiceResult] 成功時 value は Reservation
    def call
      return ServiceResult.failure(:invalid_start_at, "startAt の形式が正しくありません") if start_at.nil?

      unless reservation.confirmed?
        return ServiceResult.failure(
          :not_reschedulable, "確定済みの予約のみ日時変更できます（状態: #{reservation.status}）。"
        )
      end

      original = reservation.slice(:start_at, :end_at, :google_event_id).symbolize_keys

      unless move_slot
        return ServiceResult.failure(:slot_unavailable, "選択された時間は利用できません。")
      end

      swap_google_event(original)
    end

    private

    attr_reader :reservation, :requested_start_at, :calendar_client, :now

    def booking_type
      reservation.booking_type
    end

    def start_at
      return @start_at if defined?(@start_at)

      @start_at = begin
        parsed = requested_start_at.is_a?(String) ? Time.zone.parse(requested_start_at) : requested_start_at
        parsed if parsed && parsed.sec.zero? && parsed.usec.zero?
      rescue ArgumentError, RangeError
        nil
      end
    end

    def end_at
      start_at + booking_type.duration_minutes.minutes
    end

    # DB 上の枠を先に押さえる。押さえられなければ false（元の日時は復元済み）。
    #
    # requires_new: true でセーブポイントを張るのが要点。ネストしたトランザクションを
    # 親に相乗りさせると ActiveRecord::Rollback が無視され、変更が残ってしまう。
    # 空き確認（Google FreeBusy）をトランザクション内で行うのは、変更先の枠を
    # 押さえたまま判定する必要があるため。管理 API 専用で頻度が低いので許容する。
    def move_slot
      moved = false

      Reservation.transaction(requires_new: true) do
        reservation.update!(start_at: start_at, end_at: end_at)

        if slot_available?
          moved = true
        else
          raise ActiveRecord::Rollback
        end
      end

      reservation.reload unless moved
      moved
    rescue ActiveRecord::StatementInvalid => e
      raise unless e.cause.is_a?(PG::ExclusionViolation)

      reservation.reload
      false
    end

    def slot_available?
      AvailabilityCalculator.new(
        booking_type: booking_type,
        from: start_at.in_time_zone(booking_type.tz).to_date,
        to: start_at.in_time_zone(booking_type.tz).to_date,
        now: now,
        exclude_reservation_id: reservation.id,
        calendar_client: calendar_client
      ).slot_available?(start_at)
    rescue GoogleCalendar::Client::Error => e
      Rails.logger.error("[slot-relay] 日時変更時の空き確認に失敗しました: #{e.message}")
      false
    end

    def swap_google_event(original)
      new_event_id = calendar_client.create_event(
        calendar_id: booking_type.booking_calendar_id,
        summary: GoogleEventPresenter.summary(reservation),
        description: GoogleEventPresenter.description(reservation),
        start_at: reservation.start_at,
        end_at: reservation.end_at,
        time_zone: booking_type.time_zone,
        private_properties: { "slotRelayReservationId" => reservation.public_id }
      )

      reservation.update!(google_event_id: new_event_id)
      delete_old_event(original[:google_event_id])
      safe_deliver { GuestMailer.reservation_rescheduled(reservation, original[:start_at]).deliver_now }

      ServiceResult.success(reservation)
    rescue GoogleCalendar::Client::Error => e
      Rails.logger.error("[slot-relay] 日時変更時の Google 予定作成に失敗しました: #{e.message}")
      reservation.update!(original)
      ServiceResult.failure(:calendar_error, "カレンダーの更新に失敗しました。")
    end

    def delete_old_event(event_id)
      return if event_id.blank?

      calendar_client.delete_event(calendar_id: booking_type.booking_calendar_id, event_id: event_id)
    rescue GoogleCalendar::Client::Error => e
      # 新しい予定は作れているので予約自体は成立させる。古い予定の残骸は管理者へ通知する。
      Rails.logger.error("[slot-relay] 旧 Google 予定の削除に失敗しました: #{e.message}")
      safe_deliver { AdminMailer.calendar_error(reservation, e.message).deliver_now }
    end

    def safe_deliver
      yield
    rescue StandardError => e
      Rails.logger.error("[slot-relay] メール送信に失敗しました: #{e.class}: #{e.message}")
    end
  end
end
