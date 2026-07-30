# frozen_string_literal: true

require "test_helper"

module V1
  module Admin
    class ReservationsControllerTest < ActionDispatch::IntegrationTest
      MONDAY = BookingFactories::MONDAY

      setup do
        @booking_type = create_booking_type
        @reservation = create_confirmed_reservation(booking_type: @booking_type, start_at: jst(MONDAY, "10:00"))
      end

      test "認証が無いと 401" do
        get "/v1/admin/reservations"

        assert_response :unauthorized
      end

      test "予約一覧を返す" do
        get "/v1/admin/reservations", headers: admin_headers

        assert_response :success
        body = response.parsed_body

        assert_equal 1, body["total"]
        assert_equal @reservation.public_id, body["reservations"].first["reservationId"]
        assert_equal "existing-event", body["reservations"].first["googleEventId"]
      end

      test "キャンセルトークンのハッシュは管理 API でも返さない" do
        get "/v1/admin/reservations", headers: admin_headers

        assert_response :success
        assert_not_includes response.body, @reservation.cancel_token_hash
        assert_not_includes response.body, "cancelToken"
      end

      test "status / slug で絞り込める" do
        get "/v1/admin/reservations", params: { status: "cancelled" }, headers: admin_headers
        assert_equal 0, response.parsed_body["total"]

        get "/v1/admin/reservations", params: { status: "confirmed" }, headers: admin_headers
        assert_equal 1, response.parsed_body["total"]

        get "/v1/admin/reservations", params: { slug: "does-not-exist" }, headers: admin_headers
        assert_equal 0, response.parsed_body["total"]

        get "/v1/admin/reservations", params: { slug: @booking_type.slug }, headers: admin_headers
        assert_equal 1, response.parsed_body["total"]
      end

      test "limit は上限で丸める" do
        get "/v1/admin/reservations", params: { limit: 9999 }, headers: admin_headers

        assert_equal ReservationsController::MAX_PER_PAGE, response.parsed_body["limit"]
      end

      test "予約詳細を返す" do
        get "/v1/admin/reservations/#{@reservation.id}", headers: admin_headers

        assert_response :success
        assert_equal @reservation.id, response.parsed_body["id"]
      end

      test "管理 API から予約をキャンセルできる" do
        post "/v1/admin/reservations/#{@reservation.id}/cancel", headers: admin_headers

        assert_response :success
        assert_equal "cancelled", response.parsed_body["status"]
        assert_equal 1, fake_calendar.deleted_events.size
      end

      test "管理 API から日時変更できる" do
        freeze_base_time do
          post "/v1/admin/reservations/#{@reservation.id}/reschedule",
               params: { startAt: jst(MONDAY, "14:00").iso8601 }.to_json,
               headers: admin_headers.merge("Content-Type" => "application/json")
        end

        assert_response :success
        assert_equal "2026-08-03T14:00:00+09:00", response.parsed_body["startAt"]
        assert_equal jst(MONDAY, "14:00"), @reservation.reload.start_at
      end

      test "埋まっている時間への日時変更は 409" do
        create_confirmed_reservation(
          booking_type: @booking_type, start_at: jst(MONDAY, "14:00"), guest_email: "other@example.com"
        )

        freeze_base_time do
          post "/v1/admin/reservations/#{@reservation.id}/reschedule",
               params: { startAt: jst(MONDAY, "14:00").iso8601 }.to_json,
               headers: admin_headers.merge("Content-Type" => "application/json")
        end

        assert_response :conflict
        assert_equal "SLOT_UNAVAILABLE", response.parsed_body["code"]
      end
    end
  end
end
