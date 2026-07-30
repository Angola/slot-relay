# frozen_string_literal: true

module Reservations
  # 予約の確定処理（docs/DESIGN.md §3.3）。
  #
  #   予約 POST
  #     ↓ 入力・Turnstile・Idempotency-Key 検証
  #   DB へ pending 予約を作成して仮確保（排他制約で同時リクエストを直列化）
  #     ↓
  #   Google FreeBusy で直前確認
  #     ↓ 空いている
  #   Google Calendar へ予定作成
  #     ↓
  #   DB を confirmed へ更新 → 確認メール送信
  #
  # 空き枠を表示してから予約されるまでに Google カレンダーへ別予定が入る可能性があるため、
  # 表示時の計算結果は信用せず POST 時に再計算する。
  class Creator
    def initialize(booking_type:, params:, idempotency_key:, remote_ip: nil,
                   now: Time.current, calendar_client: SlotRelay.calendar_client,
                   turnstile: TurnstileVerifier.new)
      @booking_type = booking_type
      @params = params
      @idempotency_key = idempotency_key.presence
      @remote_ip = remote_ip
      @now = now
      @calendar_client = calendar_client
      @turnstile = turnstile
    end

    # @return [ServiceResult] 成功時 value は Reservation
    def call
      return failure(:validation_failed, "Idempotency-Key ヘッダは必須です") if idempotency_key.blank?

      # Idempotency-Key の照会は Turnstile 検証より**前**に行う。
      # Turnstile のトークンは 1 回しか検証できないため、応答を取りこぼした
      # クライアントが同じキー・同じトークンで再送すると、既存予約を返すべき場面で
      # TURNSTILE_FAILED になり、Idempotency-Key の意味が失われる。
      # 既存予約の再送は「新しい予約試行」ではないので Bot 判定をやり直す必要もない。
      if (existing = find_by_idempotency_key)
        return replay(existing)
      end

      return failure(:invalid_start_at, "startAt の形式が正しくありません") if start_at.nil?

      # 本番で TURNSTILE_SECRET_KEY を入れ忘れると、TurnstileVerifier が素通しになり
      # 予約 POST の防御がレートリミットだけになる。設定漏れを黙って許さず 503 にする。
      if SlotRelay.config.turnstile_missing?
        Rails.logger.error("[slot-relay] TURNSTILE_SECRET_KEY が未設定のため予約を受け付けません")
        return failure(:configuration_error, "予約機能が構成されていません。管理者にお問い合わせください。")
      end

      unless turnstile.verify(params[:turnstile_token], remote_ip:)
        return failure(:turnstile_failed, "Bot 判定に失敗しました。ページを再読み込みしてお試しください。")
      end

      reservation = hold_slot
      return reservation if reservation.is_a?(ServiceResult)

      confirm(reservation)
    end

    private

    attr_reader :booking_type, :params, :idempotency_key, :remote_ip, :now, :calendar_client, :turnstile

    def start_at
      return @start_at if defined?(@start_at)

      @start_at = begin
        parsed = Time.zone.parse(params[:start_at].to_s)
        # 秒・ミリ秒付きの開始時刻は枠の境界と一致しないため受け付けない
        parsed if parsed && parsed.sec.zero? && parsed.usec.zero?
      rescue ArgumentError, RangeError
        nil
      end
    end

    def end_at
      start_at + booking_type.duration_minutes.minutes
    end

    def find_by_idempotency_key
      booking_type.reservations.find_by(idempotency_key: idempotency_key)
    end

    # 同じ Idempotency-Key の再送。ネットワーク再送で二重予約にならないようにする。
    def replay(existing)
      case existing.status
      when "confirmed", "cancelled"
        ServiceResult.success(existing)
      when "pending"
        failure(:request_in_progress, "同じ Idempotency-Key の予約処理が進行中です。")
      else
        failure(:calendar_error, "この Idempotency-Key の予約は失敗しています。新しいキーで再試行してください。")
      end
    end

    # pending 予約を作って枠を仮確保する。
    # 重なりの検出は DB の排他制約（reservations_active_overlap_exclude）に任せる。
    # @return [Reservation, ServiceResult]
    def hold_slot
      reservation = nil

      # requires_new: true でセーブポイントを張る。親トランザクションに相乗りすると
      # ActiveRecord::Rollback が無視され、期限切れ pending の削除だけが残ってしまう。
      Reservation.transaction(requires_new: true) do
        # 期限切れの仮確保は排他制約から見ると生きているため、ここで掃除する。
        booking_type.reservations.expired_pending(now).delete_all

        reservation = booking_type.reservations.new(
          start_at: start_at,
          end_at: end_at,
          guest_name: params[:guest_name],
          guest_email: params[:guest_email],
          guest_company: params[:guest_company].presence,
          guest_phone: params[:guest_phone].presence,
          answers: normalized_answers,
          status: "pending",
          idempotency_key: idempotency_key,
          expires_at: now + Reservation::PENDING_TTL
        )
        reservation.issue_cancel_token!

        unless reservation.save
          @validation_errors = reservation.errors.full_messages
          raise ActiveRecord::Rollback
        end
      end

      if @validation_errors.present?
        return failure(:validation_failed, "入力内容に誤りがあります。", details: @validation_errors)
      end

      reservation
    rescue ActiveRecord::StatementInvalid => e
      raise unless e.cause.is_a?(PG::ExclusionViolation)

      # 同じ Idempotency-Key の同時リクエストは、Idempotency-Key の一意制約より先に
      # 枠の排他制約に当たることがある。その場合は「枠が埋まった」ではなく冪等な再送として扱う。
      existing = find_by_idempotency_key
      existing ? replay(existing) : slot_unavailable
    rescue ActiveRecord::RecordNotUnique
      # 同一 Idempotency-Key の同時リクエスト。先着の結果をそのまま返す。
      existing = find_by_idempotency_key
      existing ? replay(existing) : failure(:request_in_progress, "同じ Idempotency-Key の予約処理が進行中です。")
    end

    def confirm(reservation)
      unless slot_still_available?(reservation)
        reservation.destroy
        return slot_unavailable
      end

      event_id = create_google_event(reservation)
      return event_id if event_id.is_a?(ServiceResult)

      reservation.update!(status: "confirmed", google_event_id: event_id, expires_at: nil)
      deliver_notifications(reservation)

      ServiceResult.success(reservation)
    end

    # 仮確保した自分自身は除外して、Google 予定・他の予約と衝突しないか再確認する。
    def slot_still_available?(reservation)
      AvailabilityCalculator.new(
        booking_type: booking_type,
        from: reservation.start_at.in_time_zone(booking_type.tz).to_date,
        to: reservation.start_at.in_time_zone(booking_type.tz).to_date,
        now: now,
        exclude_reservation_id: reservation.id,
        calendar_client: calendar_client
      ).slot_available?(reservation.start_at)
    rescue GoogleCalendar::Client::Error => e
      Rails.logger.error("[slot-relay] 空き枠の再確認に失敗しました: #{e.message}")
      false
    end

    def create_google_event(reservation)
      calendar_client.create_event(
        calendar_id: booking_type.booking_calendar_id,
        summary: GoogleEventPresenter.summary(reservation),
        description: GoogleEventPresenter.description(reservation),
        start_at: reservation.start_at,
        end_at: reservation.end_at,
        time_zone: booking_type.time_zone,
        private_properties: { "slotRelayReservationId" => reservation.public_id }
      )
    rescue GoogleCalendar::Client::Error => e
      # 予定を作れなかった予約は成立させない。failed にすると排他制約の対象から外れ、
      # 枠は自動的に解放される。
      Rails.logger.error("[slot-relay] Google 予定の作成に失敗しました: #{e.message}")
      reservation.update!(status: "failed", expires_at: nil)
      safe_deliver { AdminMailer.calendar_error(reservation, e.message).deliver_now }

      failure(:calendar_error, "カレンダーへの登録に失敗しました。時間をおいて再度お試しください。")
    end

    # メール送信失敗を理由に予約自体は失敗させない（docs/DESIGN.md §3.5）。
    def deliver_notifications(reservation)
      safe_deliver { GuestMailer.reservation_confirmed(reservation).deliver_now }
      safe_deliver { AdminMailer.reservation_created(reservation).deliver_now }
    end

    def safe_deliver
      yield
    rescue StandardError => e
      Rails.logger.error("[slot-relay] メール送信に失敗しました: #{e.class}: #{e.message}")
    end

    def normalized_answers
      answers = params[:answers]
      return {} unless answers.is_a?(Hash)

      answers.to_h { |key, value| [key.to_s, value.to_s] }
    end

    def slot_unavailable
      failure(:slot_unavailable, "選択された時間は利用できなくなりました。")
    end

    def failure(code, message, details: nil)
      ServiceResult.failure(code, message, details:)
    end
  end
end
