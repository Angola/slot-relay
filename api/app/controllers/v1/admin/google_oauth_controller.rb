# frozen_string_literal: true

module V1
  module Admin
    # Google アカウントの連携フロー。
    #
    #   POST /v1/admin/google/oauth/url       — 同意画面の URL を発行（X-Admin-Key）
    #   GET  /v1/admin/google/oauth/callback  — 同意後に Google が戻ってくる先
    #
    # コールバックは Google からのリダイレクトなので X-Admin-Key を付けられない。
    # 代わりに state の署名で正当性を確認する（GoogleOauth::Authorization）。
    class GoogleOauthController < BaseController
      include ActionController::Cookies

      skip_before_action :authenticate_admin!, only: :callback

      def create_url
        unless SlotRelay.config.google_oauth_configured?
          return render_error(
            :configuration_error,
            "GOOGLE_OAUTH_CLIENT_ID / GOOGLE_OAUTH_CLIENT_SECRET が未設定です。"
          )
        end

        render json: {
          authUrl: GoogleOauth::Authorization.authorization_url,
          redirectUri: SlotRelay.config.google_oauth_redirect_uri_or_default,
          expiresInSeconds: GoogleOauth::Authorization::STATE_TTL.to_i
        }
      end

      def callback
        # ユーザーが同意画面で拒否した場合など
        return render_callback_error(params[:error]) if params[:error].present?

        result = GoogleOauth::Callback.new(code: params[:code], state: params[:state]).call
        return render_callback_error(result.message) if result.failure?

        # 続けてカレンダーを選べるよう、短期セッションを発行して設定画面へ送る
        session_token = GoogleOauth::SetupSession.issue
        cookies[GoogleOauth::SetupSession::COOKIE_NAME] =
          GoogleOauth::SetupSession.cookie_options.merge(value: session_token)

        redirect_to setup_path, allow_other_host: false
      end

      private

      def setup_path
        "/v1/admin/google/setup"
      end

      # コールバックはブラウザに表示されるため、JSON ではなく HTML で返す。
      def render_callback_error(message)
        Rails.logger.warn("[slot-relay] Google 連携に失敗しました: #{message}")
        render html: GoogleSetupPage.error_html(message).html_safe, # rubocop:disable Rails/OutputSafety
               content_type: "text/html",
               status: :bad_request
      end
    end
  end
end
