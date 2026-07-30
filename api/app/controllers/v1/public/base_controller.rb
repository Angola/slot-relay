# frozen_string_literal: true

module V1
  module Public
    # 予約サイトのブラウザから直接呼ばれるエンドポイントの基底クラス。
    # 秘密の API キーは使わない（サイト側に置けないため）。
    class BaseController < ApplicationController
      include PublicApi

      private

      # slug で予約メニューを引く。inactive は公開 API からは見えない。
      def booking_type
        @booking_type ||= BookingType.active.find_by!(slug: params[:slug])
      end

      # 既定では URL の slug が指す予約メニューの許可 Origin を使う。
      # apply_cors! から呼ばれるため、ここで予約メニューの解決も走る。
      def allowed_origins
        booking_type.allowed_origins
      end
    end
  end
end
