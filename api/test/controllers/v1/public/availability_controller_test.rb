# frozen_string_literal: true

require "test_helper"

module V1
  module Public
    class AvailabilityControllerTest < ActionDispatch::IntegrationTest
      MONDAY = BookingFactories::MONDAY

      setup { @booking_type = create_booking_type }

      test "空き枠をタイムゾーン付き RFC 3339 で返す" do
        freeze_base_time do
          get availability_path, params: { from: "2026-08-01", to: "2026-08-07" },
                                 headers: { "Origin" => BookingFactories::DEFAULT_ORIGIN }
        end

        assert_response :success
        body = response.parsed_body

        assert_equal "Asia/Tokyo", body["timeZone"]
        assert_equal 60, body["durationMinutes"]

        monday = body["days"].find { |day| day["date"] == "2026-08-03" }

        assert_equal 8, monday["slots"].size
        assert_equal "2026-08-03T10:00:00+09:00", monday["slots"].first["startAt"]
        assert_equal "2026-08-03T11:00:00+09:00", monday["slots"].first["endAt"]
      end

      test "土日は枠 0 件で返る" do
        freeze_base_time do
          get availability_path, params: { from: "2026-08-01", to: "2026-08-02" }
        end

        assert_response :success
        assert_equal [[], []], response.parsed_body["days"].map { |day| day["slots"] }
      end

      test "Google カレンダーに予定がある枠は含めない" do
        fake_calendar.add_busy(SlotRelayTestConfig::BUSY_CALENDAR_ID,
                               [[jst(MONDAY, "11:00"), jst(MONDAY, "12:00")]])

        freeze_base_time do
          get availability_path, params: { from: "2026-08-03", to: "2026-08-03" }
        end

        assert_response :success
        starts = response.parsed_body["days"].first["slots"].map { |slot| slot["startAt"] }

        assert_not_includes starts, "2026-08-03T11:00:00+09:00"
        assert_equal 7, starts.size
      end

      test "from / to を省略すると当日から 14 日ぶん返す" do
        freeze_base_time do
          get availability_path
        end

        assert_response :success
        days = response.parsed_body["days"]

        assert_equal 14, days.size
        assert_equal "2026-07-30", days.first["date"]
      end

      test "to が from より前なら 400" do
        get availability_path, params: { from: "2026-08-07", to: "2026-08-01" }

        assert_response :bad_request
        assert_equal "INVALID_RANGE", response.parsed_body["code"]
      end

      test "期間が長すぎると 400" do
        get availability_path, params: { from: "2026-08-01", to: "2026-12-31" }

        assert_response :bad_request
        assert_equal "INVALID_RANGE", response.parsed_body["code"]
      end

      test "日付として解釈できない値は既定値として扱う" do
        freeze_base_time do
          get availability_path, params: { from: "yesterday", to: "" }
        end

        assert_response :success
        assert_equal "2026-07-30", response.parsed_body["days"].first["date"]
      end

      test "Google から Busy 時間を取れないときは 502（空き扱いにしない）" do
        fake_calendar.raise_on_busy = true

        freeze_base_time do
          get availability_path, params: { from: "2026-08-03", to: "2026-08-03" }
        end

        assert_response :bad_gateway
        assert_equal "CALENDAR_ERROR", response.parsed_body["code"]
      end

      test "許可していない Origin は 403" do
        get availability_path, headers: { "Origin" => "https://evil.example.com" }

        assert_response :forbidden
      end

      private

      def availability_path
        "/v1/public/booking-types/#{@booking_type.slug}/availability"
      end
    end
  end
end
