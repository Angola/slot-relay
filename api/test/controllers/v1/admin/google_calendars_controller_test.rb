# frozen_string_literal: true

require "test_helper"

module V1
  module Admin
    class GoogleCalendarsControllerTest < ActionDispatch::IntegrationTest
      PATH = "/v1/admin/google/calendars"

      test "X-Admin-Key が無ければ 401" do
        get PATH

        assert_response :unauthorized
      end

      test "連携済みならカレンダー一覧と連携状態を返す" do
        connect_google!

        get PATH, headers: admin_headers

        assert_response :ok
        body = response.parsed_body

        assert body["connection"]["connected"]
        assert_equal SlotRelayTestConfig::GOOGLE_ACCOUNT_EMAIL, body["connection"]["googleAccountEmail"]
        assert_empty body["connection"]["missingScopes"]

        primary = body["calendars"].find { |c| c["primary"] }
        assert_equal "owner@example.com", primary["id"]
        assert primary["writable"]

        reader = body["calendars"].find { |c| c["id"] == "holiday@example.com" }
        assert_not reader["writable"]
      end

      test "refresh token は応答に含めない" do
        connect_google!(refresh_token: "1//super-secret")

        get PATH, headers: admin_headers

        assert_not_includes response.body, "1//super-secret"
        assert_not_includes response.body, "refreshToken"
      end

      test "未連携なら connected: false を返す" do
        get PATH, headers: admin_headers

        assert_response :ok
        assert_not response.parsed_body["connection"]["connected"]
      end

      test "カレンダー取得に失敗したら 502" do
        connect_google!
        fake_calendar.raise_on_calendars = true

        get PATH, headers: admin_headers

        assert_response :bad_gateway
        assert_equal "CALENDAR_ERROR", response.parsed_body["code"]
      end
    end
  end
end
