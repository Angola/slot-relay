# frozen_string_literal: true

require "test_helper"

module GoogleOauth
  class AuthorizationTest < ActiveSupport::TestCase
    test "同意画面の URL に必要なパラメータが揃う" do
      url = Authorization.authorization_url
      query = Rack::Utils.parse_query(URI.parse(url).query)

      assert url.start_with?(Authorization::AUTH_ENDPOINT)
      assert_equal SlotRelayTestConfig::OAUTH_CLIENT_ID, query["client_id"]
      assert_equal "code", query["response_type"]
      # refresh token を得るために両方とも必須
      assert_equal "offline", query["access_type"]
      assert_equal "consent", query["prompt"]
      assert_equal GoogleCalendar::Client::SCOPES.join(" "), query["scope"]
      assert query["state"].present?
    end

    test "全権の calendar スコープは要求しない" do
      query = Rack::Utils.parse_query(URI.parse(Authorization.authorization_url).query)

      assert_not_includes query["scope"].split(" "), "https://www.googleapis.com/auth/calendar"
    end

    test "リダイレクト URI は未設定なら PUBLIC_BASE_URL から組み立てる" do
      query = Rack::Utils.parse_query(URI.parse(Authorization.authorization_url).query)

      assert_equal "https://booking-api.example.com/v1/admin/google/oauth/callback", query["redirect_uri"]
    end

    test "リダイレクト URI は環境変数で上書きできる" do
      configure_slot_relay!(google_oauth_redirect_uri: "https://example.test/callback")
      query = Rack::Utils.parse_query(URI.parse(Authorization.authorization_url).query)

      assert_equal "https://example.test/callback", query["redirect_uri"]
    end

    test "自分が発行した state は有効" do
      assert Authorization.valid_state?(Authorization.generate_state)
    end

    test "改ざん・空・でたらめな state は無効" do
      assert_not Authorization.valid_state?(nil)
      assert_not Authorization.valid_state?("")
      assert_not Authorization.valid_state?("not-a-signed-token")
      assert_not Authorization.valid_state?("#{Authorization.generate_state}x")
    end

    test "期限切れの state は無効" do
      state = Authorization.generate_state

      travel(Authorization::STATE_TTL + 1.minute) do
        assert_not Authorization.valid_state?(state)
      end
    end
  end
end
