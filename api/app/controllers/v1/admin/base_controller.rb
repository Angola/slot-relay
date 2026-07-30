# frozen_string_literal: true

module V1
  module Admin
    # 管理 API の基底クラス。X-Admin-Key ヘッダで認証する（利用者は自分だけ）。
    #
    # 比較は ActiveSupport::SecurityUtils.secure_compare で行い、タイミング攻撃を避ける。
    # キーが未設定・短すぎる場合は 503 にして「無認証で開いている」状態を作らない。
    class BaseController < ApplicationController
      MIN_KEY_LENGTH = 32

      before_action :authenticate_admin!

      private

      def authenticate_admin!
        unless SlotRelay.config.admin_api_configured?
          Rails.logger.error("[slot-relay] ADMIN_API_KEY が未設定または短すぎます（#{MIN_KEY_LENGTH} 文字以上必要）")
          return render_error(:configuration_error, "管理 API が構成されていません。")
        end

        presented = request.headers["X-Admin-Key"].to_s
        expected = SlotRelay.config.admin_api_key

        return if presented.present? && ActiveSupport::SecurityUtils.secure_compare(presented, expected)

        render_error(:unauthorized, "X-Admin-Key が正しくありません。")
      end
    end
  end
end
