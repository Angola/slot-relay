# frozen_string_literal: true

require "test_helper"

module V1
  module Admin
    class GoogleOauthControllerTest < ActionDispatch::IntegrationTest
      TOKEN_URL = GoogleCalendar::Client::TOKEN_URI
      PRIMARY_URL = "https://www.googleapis.com/calendar/v3/users/me/calendarList/primary"

      # --- 認可 URL の発行 ---

      test "X-Admin-Key があれば認可 URL を返す" do
        post "/v1/admin/google/oauth/url", headers: admin_headers

        assert_response :ok
        body = response.parsed_body
        assert body["authUrl"].start_with?(GoogleOauth::Authorization::AUTH_ENDPOINT)
        assert_equal "https://booking-api.example.com/v1/admin/google/oauth/callback", body["redirectUri"]
      end

      test "X-Admin-Key が無ければ 401" do
        post "/v1/admin/google/oauth/url"

        assert_response :unauthorized
      end

      test "OAuth クライアント未設定なら 503" do
        configure_slot_relay!(google_oauth_client_id: nil, google_oauth_client_secret: nil)

        post "/v1/admin/google/oauth/url", headers: admin_headers

        assert_response :service_unavailable
        assert_equal "CONFIGURATION_ERROR", response.parsed_body["code"]
      end

      # --- コールバック ---

      test "同意後のコールバックで連携が保存され、設定画面へ遷移する" do
        stub_token_exchange
        stub_primary_calendar

        get "/v1/admin/google/oauth/callback", params: { code: "auth-code", state: valid_state }

        assert_redirected_to "/v1/admin/google/setup"
        assert GoogleConnection.connected?
        assert_equal "owner@example.com", GoogleConnection.current.google_account_email
      end

      test "コールバックは短期セッション Cookie を発行する" do
        stub_token_exchange
        stub_primary_calendar

        get "/v1/admin/google/oauth/callback", params: { code: "auth-code", state: valid_state }

        token = cookies[GoogleOauth::SetupSession::COOKIE_NAME.to_s]
        assert token.present?
        assert GoogleOauth::SetupSession.valid?(token)
      end

      test "コールバックは X-Admin-Key 無しで通る（Google からのリダイレクトのため）" do
        stub_token_exchange
        stub_primary_calendar

        get "/v1/admin/google/oauth/callback", params: { code: "auth-code", state: valid_state }

        assert_response :redirect
      end

      test "state が無い・偽造されている場合は連携しない" do
        get "/v1/admin/google/oauth/callback", params: { code: "auth-code", state: "forged" }

        assert_response :bad_request
        assert_nil GoogleConnection.current
        assert_not_requested :post, TOKEN_URL
      end

      test "ユーザーが同意を拒否した場合はエラー画面を出す" do
        get "/v1/admin/google/oauth/callback", params: { error: "access_denied", state: valid_state }

        assert_response :bad_request
        assert_equal "text/html", response.media_type
        assert_nil GoogleConnection.current
      end

      test "エラー画面はメッセージを HTML エスケープする" do
        get "/v1/admin/google/oauth/callback", params: { error: "<script>alert(1)</script>" }

        assert_response :bad_request
        assert_not_includes response.body, "<script>alert(1)</script>"
        assert_includes response.body, "&lt;script&gt;"
      end

      private

      def valid_state
        GoogleOauth::Authorization.generate_state
      end

      def stub_token_exchange
        stub_request(:post, TOKEN_URL).to_return(
          status: 200,
          body: {
            access_token: "at", refresh_token: "1//rt", expires_in: 3599,
            scope: GoogleCalendar::Client::SCOPES.join(" "), token_type: "Bearer"
          }.to_json,
          headers: { "Content-Type" => "application/json" }
        )
      end

      def stub_primary_calendar
        stub_request(:get, /#{Regexp.escape(PRIMARY_URL)}/).to_return(
          status: 200,
          body: { id: "owner@example.com", summary: "メイン", primary: true, accessRole: "owner" }.to_json,
          headers: { "Content-Type" => "application/json" }
        )
      end
    end
  end
end
