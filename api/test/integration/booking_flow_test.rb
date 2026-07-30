# frozen_string_literal: true

require "test_helper"

# ユースケースのテスト。docs/DESIGN.md §11「受け入れ条件」を通しで検証する。
#
#   管理 API で予約メニューを登録
#     → サイトから空き枠を取得
#     → 予約を登録（Google 予定作成・メール送信）
#     → 予約を照会
#     → キャンセル（Google 予定削除）
#     → 枠が空きに戻る
class BookingFlowTest < ActionDispatch::IntegrationTest
  MONDAY = BookingFactories::MONDAY
  SITE_ORIGIN = "https://genba-tsunagu.jp"

  test "予約メニュー登録から予約・キャンセルまで通しで動く" do
    freeze_base_time do
      # 1. 管理者が予約メニューを登録する
      post "/v1/admin/booking-types", params: booking_type_payload.to_json, headers: admin_json_headers

      assert_response :created
      slug = response.parsed_body["slug"]

      # 2. サイトが予約メニューの表示情報を取得する
      get "/v1/public/booking-types/#{slug}", headers: site_headers

      assert_response :success
      assert_equal 60, response.parsed_body["durationMinutes"]

      # 3. Google カレンダーに 1 件だけ予定を入れておく
      fake_calendar.add_busy(SlotRelayTestConfig::BUSY_CALENDAR_ID,
                             [[jst(MONDAY, "13:00"), jst(MONDAY, "14:00")]])

      # 4. サイトが空き枠を取得する（Google の予定と休業日は除外される）
      get "/v1/public/booking-types/#{slug}/availability",
          params: { from: "2026-08-03", to: "2026-08-14" }, headers: site_headers

      assert_response :success
      days = response.parsed_body["days"].index_by { |day| day["date"] }

      monday_slots = days["2026-08-03"]["slots"].map { |slot| slot["startAt"] }
      assert_includes monday_slots, "2026-08-03T10:00:00+09:00"
      assert_not_includes monday_slots, "2026-08-03T13:00:00+09:00" # Google の予定
      assert_empty days["2026-08-13"]["slots"]                       # 休業日オーバーライド
      assert_empty days["2026-08-08"]["slots"]                       # 土曜

      # 5. 予約する
      post "/v1/public/booking-types/#{slug}/reservations",
           params: reservation_payload(start_at: jst(MONDAY, "10:00")).to_json,
           headers: site_headers.merge("Content-Type" => "application/json",
                                       "Idempotency-Key" => "0198f1ab-0000-7000-8000-000000000000")

      assert_response :created
      created = response.parsed_body
      cancel_token = created.fetch("cancelUrl").split("/").last

      assert_equal "confirmed", created["status"]

      # 6. Google カレンダーに予定ができている
      assert_equal 1, fake_calendar.created_events.size
      event = fake_calendar.created_events.first
      assert_equal SlotRelayTestConfig::BOOKING_CALENDAR_ID, event[:calendar_id]
      assert_equal "【無料相談】株式会社サンプル / 山田太郎", event[:summary]

      # 7. 予約者と管理者にメールが届いている
      assert_equal 2, ActionMailer::Base.deliveries.size
      assert_equal [["taro@example.com"], ["admin@example.com"]], ActionMailer::Base.deliveries.map(&:to)

      # 8. 予約した枠は空き枠から消えている
      get "/v1/public/booking-types/#{slug}/availability",
          params: { from: "2026-08-03", to: "2026-08-03" }, headers: site_headers

      assert_not_includes response.parsed_body["days"].first["slots"].map { |slot| slot["startAt"] },
                          "2026-08-03T10:00:00+09:00"

      # 9. 予約者がトークンで照会する
      get "/v1/public/reservations/#{cancel_token}", headers: site_headers

      assert_response :success
      assert_equal created["reservationId"], response.parsed_body["reservationId"]

      # 10. キャンセルすると Google の予定も消える
      ActionMailer::Base.deliveries.clear
      post "/v1/public/reservations/#{cancel_token}/cancel", headers: site_headers

      assert_response :success
      assert_equal "cancelled", response.parsed_body["status"]
      assert_equal [event[:id]], fake_calendar.deleted_events.map { |e| e[:event_id] }
      assert_equal 2, ActionMailer::Base.deliveries.size

      # 11. 枠が空きに戻る
      get "/v1/public/booking-types/#{slug}/availability",
          params: { from: "2026-08-03", to: "2026-08-03" }, headers: site_headers

      assert_includes response.parsed_body["days"].first["slots"].map { |slot| slot["startAt"] },
                      "2026-08-03T10:00:00+09:00"
    end
  end

  test "管理 API は無認証で操作できない" do
    booking_type = create_booking_type
    reservation = create_confirmed_reservation(booking_type: booking_type, start_at: jst(MONDAY, "10:00"))

    [
      [:get, "/v1/admin/booking-types"],
      [:post, "/v1/admin/booking-types"],
      [:get, "/v1/admin/booking-types/#{booking_type.id}"],
      [:patch, "/v1/admin/booking-types/#{booking_type.id}"],
      [:delete, "/v1/admin/booking-types/#{booking_type.id}"],
      [:get, "/v1/admin/reservations"],
      [:get, "/v1/admin/reservations/#{reservation.id}"],
      [:post, "/v1/admin/reservations/#{reservation.id}/cancel"],
      [:post, "/v1/admin/reservations/#{reservation.id}/reschedule"]
    ].each do |method, path|
      process method, path, headers: { "Content-Type" => "application/json" }, params: "{}"

      assert_response :unauthorized, "#{method.upcase} #{path} が無認証で通ってしまった"
    end

    assert_predicate reservation.reload, :confirmed?
  end

  test "Google カレンダーの予定の内容は公開 API へ漏れない" do
    booking_type = create_booking_type
    fake_calendar.add_busy(SlotRelayTestConfig::BUSY_CALENDAR_ID,
                           [[jst(MONDAY, "13:00"), jst(MONDAY, "14:00")]])

    freeze_base_time do
      get "/v1/public/booking-types/#{booking_type.slug}/availability",
          params: { from: "2026-08-03", to: "2026-08-03" }, headers: site_headers
    end

    assert_response :success
    body = response.parsed_body

    # 応答は timeZone / durationMinutes / days（date と slots）のみ
    assert_equal %w[timeZone durationMinutes days].sort, body.keys.sort
    assert_equal %w[date slots].sort, body["days"].first.keys.sort
    assert_equal %w[startAt endAt].sort, body["days"].first["slots"].first.keys.sort
  end

  private

  def site_headers
    { "Origin" => SITE_ORIGIN }
  end

  def admin_json_headers
    admin_headers.merge("Content-Type" => "application/json")
  end

  def booking_type_payload
    {
      name: "無料相談",
      slug: "genba-tsunagu-consultation",
      durationMinutes: 60,
      timeZone: "Asia/Tokyo",
      minimumNoticeMinutes: 1440,
      bookingWindowDays: 30,
      googleBookingCalendarId: SlotRelayTestConfig::BOOKING_CALENDAR_ID,
      allowedOrigins: [SITE_ORIGIN],
      weeklyAvailability: (1..5).map { |day| { dayOfWeek: day, startTime: "10:00", endTime: "18:00" } },
      availabilityOverrides: [{ date: "2026-08-13", isAvailable: false }]
    }
  end
end
