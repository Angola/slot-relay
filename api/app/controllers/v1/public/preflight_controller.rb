# frozen_string_literal: true

module V1
  module Public
    # 公開 API の CORS プリフライト（OPTIONS）。
    #
    # プリフライトはボディを持たず、URL から予約メニューを特定するのは脆いため、
    # ここでは「いずれかの予約メニューが許可している Origin か」だけを判定する。
    # 予約メニュー単位の厳密な検証は本リクエスト（PublicApi#apply_cors!）で行う。
    class PreflightController < ApplicationController
      def handle
        origin = request.headers["Origin"].presence
        response.headers["Vary"] = "Origin"

        return head :forbidden unless origin && OriginAllowList.allowed?(origin)

        response.headers["Access-Control-Allow-Origin"] = origin
        response.headers["Access-Control-Allow-Methods"] = PublicApi::ALLOWED_METHODS
        response.headers["Access-Control-Allow-Headers"] = PublicApi::ALLOWED_HEADERS
        response.headers["Access-Control-Max-Age"] = PublicApi::MAX_AGE

        head :no_content
      end
    end
  end
end
