# frozen_string_literal: true

require "test_helper"

class GoogleConnectionTest < ActiveSupport::TestCase
  test "refresh token は暗号化して保存され、DB には平文が残らない" do
    connection = connect_google!(refresh_token: "1//super-secret-refresh-token")

    raw = GoogleConnection.connection.select_value(
      "select encrypted_refresh_token from google_connections where id = #{connection.id}"
    )

    assert_not_includes raw, "1//super-secret-refresh-token"
    assert_equal "1//super-secret-refresh-token", GoogleConnection.current.refresh_token
  end

  test "connect! は連携を 1 件に保つ（別アカウントで上書きされる）" do
    connect_google!(email: "first@example.com")
    connect_google!(email: "second@example.com")

    assert_equal 1, GoogleConnection.count
    assert_equal "second@example.com", GoogleConnection.current.google_account_email
  end

  test "同じアカウントで連携し直すとトークンが差し替わる" do
    connect_google!(refresh_token: "old-token")
    connect_google!(refresh_token: "new-token")

    assert_equal 1, GoogleConnection.count
    assert_equal "new-token", GoogleConnection.current.refresh_token
  end

  test "復号できない暗号文は nil を返し、未連携として扱う" do
    connection = connect_google!
    connection.update_column(:encrypted_refresh_token, "壊れた暗号文")

    reloaded = GoogleConnection.current

    assert_nil reloaded.refresh_token
    assert_not reloaded.usable?
    assert_not GoogleConnection.connected?
  end

  test "同意されなかったスコープを missing_scopes で拾える" do
    granted = GoogleCalendar::Client::SCOPES.first(2)
    connection = connect_google!(scopes: granted)

    assert_equal GoogleCalendar::Client::SCOPES - granted, connection.missing_scopes
  end

  test "disconnect! で連携が消える" do
    connect_google!
    assert GoogleConnection.connected?

    GoogleConnection.disconnect!

    assert_not GoogleConnection.connected?
    assert_nil GoogleConnection.current
  end
end
