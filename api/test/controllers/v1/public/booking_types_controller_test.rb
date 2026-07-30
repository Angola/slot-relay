# frozen_string_literal: true

require "test_helper"

module V1
  module Public
    class BookingTypesControllerTest < ActionDispatch::IntegrationTest
      setup { @booking_type = create_booking_type }

      test "予約メニューの公開情報を返す" do
        get "/v1/public/booking-types/#{@booking_type.slug}",
            headers: { "Origin" => BookingFactories::DEFAULT_ORIGIN }

        assert_response :success
        body = response.parsed_body

        assert_equal "genba-tsunagu-consultation", body["slug"]
        assert_equal "無料相談", body["name"]
        assert_equal 60, body["durationMinutes"]
        assert_equal "Asia/Tokyo", body["timeZone"]
        assert_equal 1440, body["minimumNoticeMinutes"]
        assert_equal 30, body["bookingWindowDays"]
      end

      test "内部設定（バッファ・登録先カレンダー）は公開しない" do
        get "/v1/public/booking-types/#{@booking_type.slug}"

        assert_response :success
        body = response.parsed_body

        assert_not body.key?("googleBookingCalendarId")
        assert_not body.key?("bufferBeforeMinutes")
        assert_not body.key?("allowedOrigins")
        assert_not body.key?("id")
      end

      test "許可 Origin には CORS ヘッダを返す" do
        get "/v1/public/booking-types/#{@booking_type.slug}",
            headers: { "Origin" => BookingFactories::DEFAULT_ORIGIN }

        assert_response :success
        assert_equal BookingFactories::DEFAULT_ORIGIN, response.headers["Access-Control-Allow-Origin"]
        assert_includes response.headers["Vary"].to_s, "Origin"
      end

      test "許可していない Origin は 403" do
        get "/v1/public/booking-types/#{@booking_type.slug}",
            headers: { "Origin" => "https://evil.example.com" }

        assert_response :forbidden
        assert_equal "FORBIDDEN_ORIGIN", response.parsed_body["code"]
        assert_nil response.headers["Access-Control-Allow-Origin"]
      end

      test "Origin ヘッダが無いリクエスト（サーバー間・curl）は許可する" do
        get "/v1/public/booking-types/#{@booking_type.slug}"

        assert_response :success
      end

      test "受付停止中（inactive）の予約メニューは 404" do
        @booking_type.update!(status: "inactive")

        get "/v1/public/booking-types/#{@booking_type.slug}"

        assert_response :not_found
        assert_equal "NOT_FOUND", response.parsed_body["code"]
      end

      test "存在しない slug は 404" do
        get "/v1/public/booking-types/does-not-exist"

        assert_response :not_found
      end

      test "プリフライト（OPTIONS）は許可 Origin にのみ 204 を返す" do
        process :options, "/v1/public/booking-types/#{@booking_type.slug}/reservations",
                headers: { "Origin" => BookingFactories::DEFAULT_ORIGIN }

        assert_response :no_content
        assert_equal BookingFactories::DEFAULT_ORIGIN, response.headers["Access-Control-Allow-Origin"]
        assert_includes response.headers["Access-Control-Allow-Headers"].to_s, "Idempotency-Key"

        process :options, "/v1/public/booking-types/#{@booking_type.slug}/reservations",
                headers: { "Origin" => "https://evil.example.com" }

        assert_response :forbidden
      end
    end
  end
end
