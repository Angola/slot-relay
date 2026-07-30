# frozen_string_literal: true

module V1
  module Public
    # GET /v1/public/booking-types/:slug
    #
    # 予約画面がメニュー名・所要時間・タイムゾーンを表示するために呼ぶ。
    class BookingTypesController < BaseController
      def show
        render json: BookingTypeSerializer.public_payload(booking_type)
      end
    end
  end
end
