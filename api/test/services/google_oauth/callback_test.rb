# frozen_string_literal: true

require "test_helper"

module GoogleOauth
  # 認可コード → refresh token の交換。Google への HTTP は WebMock で止める。
  class CallbackTest < ActiveSupport::TestCase
    TOKEN_URL = GoogleCalendar::Client::TOKEN_URI
    PRIMARY_URL = "https://www.googleapis.com/calendar/v3/users/me/calendarList/primary"

    test "認可コードを交換して連携を保存する" do
      stub_token_exchange
      stub_primary_calendar

      result = Callback.new(code: "auth-code", state: valid_state).call

      assert result.success?
      connection = GoogleConnection.current
      assert_equal "owner@example.com", connection.google_account_email
      assert_equal "1//returned-refresh-token", connection.refresh_token
      assert_equal GoogleCalendar::Client::SCOPES, connection.scopes
    end

    test "state が無効なら交換しない" do
      result = Callback.new(code: "auth-code", state: "tampered").call

      assert result.failure?
      assert_equal :bad_request, result.code
      assert_nil GoogleConnection.current
      assert_not_requested :post, TOKEN_URL
    end

    test "期限切れの state を拒否する" do
      state = valid_state

      travel(Authorization::STATE_TTL + 1.minute) do
        result = Callback.new(code: "auth-code", state: state).call

        assert result.failure?
        assert_nil GoogleConnection.current
      end
    end

    test "認可コードが無ければ失敗する" do
      result = Callback.new(code: "", state: valid_state).call

      assert result.failure?
      assert_equal :bad_request, result.code
    end

    test "refresh token が返らない場合は保存せず、対処を案内する" do
      stub_token_exchange(body: { access_token: "at", scope: GoogleCalendar::Client::SCOPES.join(" ") })

      result = Callback.new(code: "auth-code", state: valid_state).call

      assert result.failure?
      assert_nil GoogleConnection.current
      assert_match(/権限を削除/, result.message)
    end

    test "トークン交換に失敗したら連携しない" do
      stub_request(:post, TOKEN_URL).to_return(status: 400, body: '{"error":"invalid_grant"}',
                                               headers: { "Content-Type" => "application/json" })

      result = Callback.new(code: "auth-code", state: valid_state).call

      assert result.failure?
      assert_equal :bad_request, result.code
      assert_nil GoogleConnection.current
    end

    test "OAuth クライアント未設定なら 503 相当で失敗する" do
      configure_slot_relay!(google_oauth_client_id: nil, google_oauth_client_secret: nil)

      result = Callback.new(code: "auth-code", state: valid_state).call

      assert result.failure?
      assert_equal :configuration_error, result.code
    end

    test "一部のスコープしか同意されなかったらそのまま記録する" do
      granted = GoogleCalendar::Client::SCOPES.first(1)
      stub_token_exchange(body: {
        access_token: "at", refresh_token: "1//token", scope: granted.join(" ")
      })
      stub_primary_calendar

      result = Callback.new(code: "auth-code", state: valid_state).call

      assert result.success?
      assert_equal granted, result.value.scopes
      assert_equal GoogleCalendar::Client::SCOPES - granted, result.value.missing_scopes
    end

    private

    def valid_state
      Authorization.generate_state
    end

    def stub_token_exchange(body: nil)
      payload = body || {
        access_token: "test-access-token",
        refresh_token: "1//returned-refresh-token",
        expires_in: 3599,
        scope: GoogleCalendar::Client::SCOPES.join(" "),
        token_type: "Bearer"
      }

      stub_request(:post, TOKEN_URL)
        .to_return(status: 200, body: payload.to_json, headers: { "Content-Type" => "application/json" })
    end

    def stub_primary_calendar(id: "owner@example.com")
      stub_request(:get, /#{Regexp.escape(PRIMARY_URL)}/)
        .to_return(status: 200,
                   body: { id: id, summary: "メイン", primary: true, accessRole: "owner" }.to_json,
                   headers: { "Content-Type" => "application/json" })
    end
  end
end
