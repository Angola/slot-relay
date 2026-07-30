# frozen_string_literal: true

require "test_helper"

# 「連携する → カレンダーを選ぶ → その選択が空き枠計算に効く」という一連の流れ。
# 個々の部品ではなく、業務フローとして繋がっていることを確かめる。
class GoogleConnectionFlowTest < ActionDispatch::IntegrationTest
  TOKEN_URL = GoogleCalendar::Client::TOKEN_URI
  PRIMARY_URL = "https://www.googleapis.com/calendar/v3/users/me/calendarList/primary"

  setup do
    @booking_type = create_booking_type
    travel_to BookingFactories::BASE_TIME
  end

  teardown { travel_back }

  test "認可 URL の発行 → 同意 → カレンダー選択 → 空き枠に反映される" do
    # 1. 認可 URL を発行する
    post "/v1/admin/google/oauth/url", headers: admin_headers
    assert_response :ok
    auth_url = response.parsed_body["authUrl"]
    state = Rack::Utils.parse_query(URI.parse(auth_url).query).fetch("state")

    # 2. Google の同意画面から戻ってくる
    stub_token_exchange
    stub_primary_calendar
    get "/v1/admin/google/oauth/callback", params: { code: "auth-code", state: state }
    assert_redirected_to "/v1/admin/google/setup"

    # 3. 設定画面が開ける（コールバックが発行した Cookie で）
    follow_redirect!
    assert_response :ok
    assert_includes response.body, "owner@example.com"

    # 4. カレンダーを選んで保存する
    session_token = cookies[GoogleOauth::SetupSession::COOKIE_NAME.to_s]
    post "/v1/admin/google/setup", params: {
      csrfToken: GoogleOauth::SetupSession.csrf_token_for(session_token),
      booking_types: {
        @booking_type.id.to_s => {
          booking_calendar_id: "booking@example.com",
          busy_calendar_ids: ["", "owner@example.com"]
        }
      }
    }
    assert_response :ok
    assert_equal %w[owner@example.com], @booking_type.reload.google_busy_calendar_ids

    # 5. 選んだカレンダーの予定が空き枠から外れる
    fake_calendar.add_busy("owner@example.com", [[jst(BookingFactories::MONDAY, "10:00"),
                                                  jst(BookingFactories::MONDAY, "11:00")]])

    get "/v1/public/booking-types/#{@booking_type.slug}/availability",
        params: { from: BookingFactories::MONDAY.iso8601, to: BookingFactories::MONDAY.iso8601 },
        headers: { "Origin" => BookingFactories::DEFAULT_ORIGIN }

    assert_response :ok
    slots = response.parsed_body["days"].first["slots"].map { |s| s["startAt"] }
    assert_not_includes slots, jst(BookingFactories::MONDAY, "10:00").iso8601
    assert_includes slots, jst(BookingFactories::MONDAY, "11:00").iso8601
  end

  test "選んでいないカレンダーの予定は空き枠に影響しない" do
    connect_google!
    @booking_type.update!(google_busy_calendar_ids: ["owner@example.com"])

    # 選択していないカレンダーに予定を入れる
    fake_calendar.add_busy("holiday@example.com", [[jst(BookingFactories::MONDAY, "10:00"),
                                                    jst(BookingFactories::MONDAY, "11:00")]])

    get "/v1/public/booking-types/#{@booking_type.slug}/availability",
        params: { from: BookingFactories::MONDAY.iso8601, to: BookingFactories::MONDAY.iso8601 },
        headers: { "Origin" => BookingFactories::DEFAULT_ORIGIN }

    slots = response.parsed_body["days"].first["slots"].map { |s| s["startAt"] }
    assert_includes slots, jst(BookingFactories::MONDAY, "10:00").iso8601
  end

  test "連携を解除すると空き取得が 502 になる（黙って全部空きにしない）" do
    connect_google!
    # 本番と同じく「未連携なら使えないクライアント」を返す状態にする
    SlotRelay.calendar_client = GoogleCalendar::UnavailableClient.new("未連携")

    get "/v1/public/booking-types/#{@booking_type.slug}/availability",
        params: { from: BookingFactories::MONDAY.iso8601, to: BookingFactories::MONDAY.iso8601 },
        headers: { "Origin" => BookingFactories::DEFAULT_ORIGIN }

    assert_response :bad_gateway
    assert_equal "CALENDAR_ERROR", response.parsed_body["code"]
  end

  private

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
