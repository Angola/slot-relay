# frozen_string_literal: true

module V1
  module Admin
    # Google 連携の設定画面（サーバー描画の HTML）。
    #
    #   GET  /v1/admin/google/setup       — 連携状態とカレンダー選択の画面
    #   POST /v1/admin/google/setup       — 選択を保存
    #   POST /v1/admin/google/disconnect  — 連携を解除
    #
    # 認証は次のどちらか。
    #   - コールバックが発行した短期セッション Cookie（30 分・SameSite=Strict）
    #   - X-Admin-Key ヘッダ（API クライアントから触るとき）
    #
    # Cookie で認証する唯一の画面なので、POST には CSRF トークンを必須にする。
    class GoogleSetupController < BaseController
      include ActionController::Cookies

      skip_before_action :authenticate_admin!
      before_action :authenticate_setup!
      before_action :verify_csrf!, only: %i[update disconnect]

      def show
        render_page
      end

      def update
        saved = GoogleCalendarSelection.new(selection_params).call

        if saved.failure?
          render_page(error: saved.message, status: :unprocessable_content)
        else
          render_page(notice: "カレンダーの設定を保存しました。")
        end
      end

      def disconnect
        GoogleConnection.disconnect!
        Rails.logger.info("[slot-relay] Google 連携を解除しました")
        render_page(notice: "Google 連携を解除しました。")
      end

      private

      # 短期セッション Cookie か X-Admin-Key のどちらかがあればよい。
      def authenticate_setup!
        return if GoogleOauth::SetupSession.valid?(session_cookie)
        return if admin_key_valid?

        render html: GoogleSetupPage.unauthorized_html.html_safe, # rubocop:disable Rails/OutputSafety
               content_type: "text/html",
               status: :unauthorized
      end

      # Cookie で認証している場合のみ CSRF トークンを検証する。
      # X-Admin-Key はブラウザが自動送信しないため、そもそも CSRF が成立しない。
      def verify_csrf!
        return if admin_key_valid?
        return if GoogleOauth::SetupSession.valid_csrf?(session_cookie, params[:csrfToken])

        render html: GoogleSetupPage.error_html(
          "フォームの有効期限が切れています。画面を開き直してください。"
        ).html_safe, content_type: "text/html", status: :forbidden # rubocop:disable Rails/OutputSafety
      end

      def admin_key_valid?
        return false unless SlotRelay.config.admin_api_configured?

        presented = request.headers["X-Admin-Key"].to_s
        presented.present? &&
          ActiveSupport::SecurityUtils.secure_compare(presented, SlotRelay.config.admin_api_key)
      end

      def session_cookie
        cookies[GoogleOauth::SetupSession::COOKIE_NAME]
      end

      def render_page(notice: nil, error: nil, status: :ok)
        html = GoogleSetupPage.new(
          connection: GoogleConnection.current,
          calendars: available_calendars,
          booking_types: BookingType.order(:name).to_a,
          csrf_token: GoogleOauth::SetupSession.csrf_token_for(session_cookie),
          notice: notice,
          error: error || @calendar_error
        ).render

        render html: html.html_safe, content_type: "text/html", status: status # rubocop:disable Rails/OutputSafety
      end

      # 未連携やトークン失効でも画面自体は開けるようにする（そこから再連携するため）。
      def available_calendars
        return [] unless GoogleConnection.connected?

        SlotRelay.calendar_client.calendars
      rescue GoogleCalendar::Client::Error => e
        @calendar_error = "カレンダー一覧を取得できませんでした: #{e.message}"
        []
      end

      # booking_types[<id>][booking_calendar_id] / [busy_calendar_ids][]
      # マスアサインメントは行わず、ID と文字列だけを取り出す。
      def selection_params
        raw = params[:booking_types]
        return {} unless raw.respond_to?(:each_pair)

        raw.to_unsafe_h.each_with_object({}) do |(booking_type_id, attrs), acc|
          next unless attrs.respond_to?(:[])

          acc[booking_type_id.to_i] = {
            booking_calendar_id: string_or_nil(attrs["booking_calendar_id"]),
            busy_calendar_ids: Array(attrs["busy_calendar_ids"]).grep(String).reject(&:blank?)
          }
        end
      end

      def string_or_nil(value)
        value.is_a?(String) && value.present? ? value : nil
      end
    end
  end
end
