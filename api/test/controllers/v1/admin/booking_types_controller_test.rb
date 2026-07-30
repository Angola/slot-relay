# frozen_string_literal: true

require "test_helper"

module V1
  module Admin
    class BookingTypesControllerTest < ActionDispatch::IntegrationTest
      PAYLOAD = {
        name: "無料相談",
        slug: "genba-tsunagu-consultation",
        durationMinutes: 60,
        timeZone: "Asia/Tokyo",
        minimumNoticeMinutes: 1440,
        bookingWindowDays: 30,
        allowedOrigins: ["https://genba-tsunagu.jp"],
        weeklyAvailability: [
          { dayOfWeek: 1, startTime: "10:00", endTime: "18:00" },
          { dayOfWeek: 2, startTime: "10:00", endTime: "18:00" }
        ]
      }.freeze

      test "X-Admin-Key が無いと 401" do
        get "/v1/admin/booking-types"

        assert_response :unauthorized
        assert_equal "UNAUTHORIZED", response.parsed_body["code"]
      end

      test "X-Admin-Key が違うと 401" do
        get "/v1/admin/booking-types", headers: admin_headers(key: "wrong-key-but-long-enough-0123456789ab")

        assert_response :unauthorized
      end

      test "ADMIN_API_KEY が未設定なら 503（無認証で開かない）" do
        configure_slot_relay!(admin_api_key: nil)

        get "/v1/admin/booking-types", headers: { "X-Admin-Key" => "" }

        assert_response :service_unavailable
        assert_equal "CONFIGURATION_ERROR", response.parsed_body["code"]
      end

      test "ADMIN_API_KEY が短すぎると 503" do
        configure_slot_relay!(admin_api_key: "short")

        get "/v1/admin/booking-types", headers: { "X-Admin-Key" => "short" }

        assert_response :service_unavailable
      end

      test "予約メニューを登録できる" do
        post "/v1/admin/booking-types", params: PAYLOAD.to_json, headers: json_admin_headers

        assert_response :created
        body = response.parsed_body

        assert_equal "genba-tsunagu-consultation", body["slug"]
        assert_equal ["https://genba-tsunagu.jp"], body["allowedOrigins"]
        assert_equal 2, body["weeklyAvailability"].size
        assert_equal({ "dayOfWeek" => 1, "startTime" => "10:00", "endTime" => "18:00" },
                     body["weeklyAvailability"].first)
        assert_equal "active", body["status"]
      end

      test "同じ slug は 422" do
        post "/v1/admin/booking-types", params: PAYLOAD.to_json, headers: json_admin_headers
        post "/v1/admin/booking-types", params: PAYLOAD.to_json, headers: json_admin_headers

        assert_response 422
        assert_equal "VALIDATION_FAILED", response.parsed_body["code"]
        assert_predicate response.parsed_body["details"], :present?
      end

      test "受付時間の時刻が不正なら 422 で該当インデックスを返す" do
        payload = PAYLOAD.merge(weeklyAvailability: [{ dayOfWeek: 1, startTime: "25:00", endTime: "18:00" }])

        post "/v1/admin/booking-types", params: payload.to_json, headers: json_admin_headers

        assert_response 422
        assert_includes response.parsed_body["details"].join, "weeklyAvailability[0]"
        assert_equal 0, BookingType.count
      end

      test "許可 Origin の形式が不正なら 422" do
        payload = PAYLOAD.merge(allowedOrigins: ["https://genba-tsunagu.jp/booking"])

        post "/v1/admin/booking-types", params: payload.to_json, headers: json_admin_headers

        assert_response 422
        assert_includes response.parsed_body["details"].join, "allowedOrigins[0]"
      end

      test "特定日の休業設定を登録できる" do
        payload = PAYLOAD.merge(availabilityOverrides: [
                                  { date: "2026-08-13", isAvailable: false },
                                  { date: "2026-08-14", isAvailable: true, startTime: "13:00", endTime: "17:00" }
                                ])

        post "/v1/admin/booking-types", params: payload.to_json, headers: json_admin_headers

        assert_response :created
        overrides = response.parsed_body["availabilityOverrides"]

        assert_equal 2, overrides.size
        assert_equal false, overrides.first["isAvailable"]
        assert_nil overrides.first["startTime"]
        assert_equal "13:00", overrides.second["startTime"]
      end

      test "一覧・詳細を取得できる" do
        booking_type = create_booking_type

        get "/v1/admin/booking-types", headers: admin_headers
        assert_response :success
        assert_equal 1, response.parsed_body["bookingTypes"].size

        get "/v1/admin/booking-types/#{booking_type.id}", headers: admin_headers
        assert_response :success
        assert_equal booking_type.id, response.parsed_body["id"]
      end

      test "PATCH は送られたキーだけを更新する" do
        booking_type = create_booking_type

        patch "/v1/admin/booking-types/#{booking_type.id}",
              params: { minimumNoticeMinutes: 120 }.to_json, headers: json_admin_headers

        assert_response :success
        booking_type.reload

        assert_equal 120, booking_type.minimum_notice_minutes
        assert_equal "無料相談", booking_type.name
        assert_equal 5, booking_type.weekly_availabilities.count
      end

      test "weeklyAvailability を送ると全置換する" do
        booking_type = create_booking_type

        patch "/v1/admin/booking-types/#{booking_type.id}",
              params: { weeklyAvailability: [{ dayOfWeek: 6, startTime: "09:00", endTime: "12:00" }] }.to_json,
              headers: json_admin_headers

        assert_response :success
        assert_equal [6], booking_type.reload.weekly_availabilities.map(&:day_of_week)
      end

      test "更新に失敗したら元の状態を保つ" do
        booking_type = create_booking_type

        patch "/v1/admin/booking-types/#{booking_type.id}",
              params: {
                name: "変更後",
                weeklyAvailability: [{ dayOfWeek: 9, startTime: "09:00", endTime: "12:00" }]
              }.to_json,
              headers: json_admin_headers

        assert_response 422
        booking_type.reload

        assert_equal "無料相談", booking_type.name
        assert_equal 5, booking_type.weekly_availabilities.count
      end

      test "予約が無い予約メニューは削除できる" do
        booking_type = create_booking_type

        delete "/v1/admin/booking-types/#{booking_type.id}", headers: admin_headers

        assert_response :no_content
        assert_equal 0, BookingType.count
      end

      test "予約がある予約メニューは削除できず 422" do
        booking_type = create_booking_type
        create_confirmed_reservation(booking_type: booking_type, start_at: jst(BookingFactories::MONDAY, "10:00"))

        delete "/v1/admin/booking-types/#{booking_type.id}", headers: admin_headers

        assert_response 422
        assert_equal 1, BookingType.count
      end

      test "存在しない id は 404" do
        get "/v1/admin/booking-types/999999", headers: admin_headers

        assert_response :not_found
      end

      private

      def json_admin_headers
        admin_headers.merge("Content-Type" => "application/json")
      end
    end
  end
end
