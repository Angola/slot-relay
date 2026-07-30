# frozen_string_literal: true

module V1
  module Public
    # 予約の登録・照会・キャンセル。
    #
    #   POST /v1/public/booking-types/:slug/reservations
    #   GET  /v1/public/reservations/:public_token
    #   POST /v1/public/reservations/:public_token/cancel
    #
    # 照会・キャンセルは URL の生トークン（メールに載せた本人確認用シークレット）で認可する。
    # public_id を知っているだけでは他人の予約を読めない・キャンセルできない。
    class ReservationsController < BaseController
      def create
        result = Reservations::Creator.new(
          booking_type: booking_type,
          params: reservation_params,
          idempotency_key: request.headers["Idempotency-Key"],
          remote_ip: request.remote_ip
        ).call

        return render_service_failure(result) if result.failure?

        render json: ReservationSerializer.public_payload(result.value, include_cancel_url: true), status: :created
      end

      def show
        render json: ReservationSerializer.public_payload(reservation_by_token)
      end

      def cancel
        result = Reservations::Canceller.new(reservation: reservation_by_token).call

        return render_service_failure(result) if result.failure?

        render json: ReservationSerializer.public_payload(result.value)
      end

      private

      # トークン照会系では、予約が属する予約メニューの許可 Origin を使う。
      def allowed_origins
        return super if params[:public_token].blank?

        reservation_by_token.booking_type.allowed_origins
      end

      def reservation_by_token
        @reservation_by_token ||=
          Reservation.find_by_cancel_token(params[:public_token]) || raise(ActiveRecord::RecordNotFound)
      end

      # リクエストボディは camelCase のフラット構造（docs/DESIGN.md §3.4）。
      # マスアサインメントは一切行わないため strong parameters には通さず、
      # 必要な値だけを型を固定して取り出す。
      def reservation_params
        {
          start_at: string_param(params[:startAt]),
          turnstile_token: string_param(params[:turnstileToken]),
          guest_name: string_param(guest_param(:name)),
          guest_email: string_param(guest_param(:email)),
          guest_company: string_param(guest_param(:company)),
          guest_phone: string_param(guest_param(:phone)),
          answers: answers_param
        }
      end

      def guest_param(key)
        guest = params[:guest]
        return nil unless guest.respond_to?(:[]) && !guest.is_a?(Array) && !guest.is_a?(String)

        guest[key]
      end

      # 配列・ハッシュを文字列カラムへ流し込まれないようにする（パラメータ汚染対策）。
      def string_param(value)
        value.is_a?(String) ? value : nil
      end

      # answers は予約メニューごとに項目が変わるためキーを固定できない。
      # ここでは文字列のマップに正規化するだけにとどめ、件数・長さは Reservation で検証する。
      def answers_param
        raw = params[:answers]
        return {} unless raw.respond_to?(:to_unsafe_h)
        return {} if raw.is_a?(Array)

        raw.to_unsafe_h.to_h { |key, value| [key.to_s, value.is_a?(String) ? value : value.to_s] }
      end
    end
  end
end
