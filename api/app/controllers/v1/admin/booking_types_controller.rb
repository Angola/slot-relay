# frozen_string_literal: true

module V1
  module Admin
    # 予約メニューの CRUD。初期設定は curl / API クライアントから行う（管理画面は MVP 対象外）。
    class BookingTypesController < BaseController
      before_action :load_booking_type, only: %i[show update destroy]

      def index
        booking_types = BookingType.includes(:origins, :weekly_availabilities, :availability_overrides)
                                   .order(:slug)

        render json: { bookingTypes: booking_types.map { |bt| BookingTypeSerializer.admin_payload(bt) } }
      end

      def show
        render json: BookingTypeSerializer.admin_payload(@booking_type)
      end

      def create
        result = BookingTypes::Upsert.new(booking_type: BookingType.new, payload: payload).call

        return render_service_failure(result) if result.failure?

        render json: BookingTypeSerializer.admin_payload(result.value), status: :created
      end

      def update
        result = BookingTypes::Upsert.new(booking_type: @booking_type, payload: payload).call

        return render_service_failure(result) if result.failure?

        render json: BookingTypeSerializer.admin_payload(result.value)
      end

      def destroy
        # 予約が紐づいている予約メニューは消さない（履歴を失うため）。
        # 受付を止めたいだけなら status を inactive にする。
        if @booking_type.destroy
          OriginAllowList.reset!
          head :no_content
        else
          render_error(:validation_failed, "予約が存在するため削除できません。status を inactive にしてください。",
                       details: @booking_type.errors.full_messages)
        end
      end

      private

      def load_booking_type
        @booking_type = BookingType.find(params[:id])
      end

      # マスアサインメントは Upsert 側で許可キーを明示するため、ここでは生のハッシュを渡す。
      def payload
        params.except(:controller, :action, :format, :id, :booking_type).to_unsafe_h
      end
    end
  end
end
