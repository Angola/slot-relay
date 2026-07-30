# frozen_string_literal: true

require "test_helper"

module V1
  module Public
    class ReservationsControllerTest < ActionDispatch::IntegrationTest
      MONDAY = BookingFactories::MONDAY

      setup do
        @booking_type = create_booking_type
        @start_at = jst(MONDAY, "10:00")
      end

      test "予約を登録すると 201 とキャンセル URL を返す" do
        freeze_base_time { post_reservation }

        assert_response :created
        body = response.parsed_body

        assert_equal "confirmed", body["status"]
        assert_equal "2026-08-03T10:00:00+09:00", body["startAt"]
        assert_equal "2026-08-03T11:00:00+09:00", body["endAt"]
        assert_match(/\Ares_/, body["reservationId"])
        assert_match %r{\Ahttps://booking-api\.example\.com/c/#{body["reservationId"]}/}, body["cancelUrl"]
        assert_equal "genba-tsunagu-consultation", body.dig("bookingType", "slug")
      end

      test "キャンセルトークンのハッシュは応答に含めない" do
        freeze_base_time { post_reservation }

        assert_response :created
        assert_not_includes response.body, Reservation.sole.cancel_token_hash
      end

      test "Idempotency-Key が無いと 422" do
        freeze_base_time { post_reservation(idempotency_key: nil) }

        assert_response 422
        assert_equal "VALIDATION_FAILED", response.parsed_body["code"]
      end

      test "同じ枠への 2 件目は 409 SLOT_UNAVAILABLE" do
        freeze_base_time do
          post_reservation(idempotency_key: "key-1")
          assert_response :created

          post_reservation(idempotency_key: "key-2")
        end

        assert_response :conflict
        assert_equal "SLOT_UNAVAILABLE", response.parsed_body["code"]
        assert_equal "選択された時間は利用できなくなりました。", response.parsed_body["message"]
      end

      test "同じ Idempotency-Key の再送は同じ予約を返す" do
        freeze_base_time do
          post_reservation(idempotency_key: "key-1")
          first_id = response.parsed_body["reservationId"]

          post_reservation(idempotency_key: "key-1")

          assert_response :created
          assert_equal first_id, response.parsed_body["reservationId"]
        end

        assert_equal 1, Reservation.count
      end

      test "guest が無いと 422" do
        freeze_base_time do
          post reservations_path,
               params: { startAt: @start_at.iso8601 }.to_json,
               headers: json_headers(idempotency_key: "key-1")
        end

        assert_response 422
        assert_equal "VALIDATION_FAILED", response.parsed_body["code"]
      end

      test "guest.name にオブジェクトを入れても落ちない（パラメータ汚染対策）" do
        freeze_base_time do
          post reservations_path,
               params: { startAt: @start_at.iso8601, guest: { name: { "$ne" => 1 }, email: "a@example.com" } }.to_json,
               headers: json_headers(idempotency_key: "key-1")
        end

        assert_response 422
        assert_equal "VALIDATION_FAILED", response.parsed_body["code"]
      end

      test "許可していない Origin からは予約できない" do
        freeze_base_time { post_reservation(origin: "https://evil.example.com") }

        assert_response :forbidden
        assert_equal 0, Reservation.count
      end

      test "トークンで予約を照会できる" do
        freeze_base_time { post_reservation }
        token = cancel_token_from_response

        get "/v1/public/reservations/#{token}", headers: { "Origin" => BookingFactories::DEFAULT_ORIGIN }

        assert_response :success
        assert_equal Reservation.sole.public_id, response.parsed_body["reservationId"]
        assert_equal "山田太郎", response.parsed_body.dig("guest", "name")
      end

      test "public_id を知っているだけでは照会できない" do
        freeze_base_time { post_reservation }

        get "/v1/public/reservations/#{Reservation.sole.public_id}"

        assert_response :not_found
      end

      test "トークンで予約をキャンセルできる" do
        freeze_base_time { post_reservation }
        token = cancel_token_from_response

        post "/v1/public/reservations/#{token}/cancel"

        assert_response :success
        assert_equal "cancelled", response.parsed_body["status"]
        assert_predicate Reservation.sole, :cancelled?
        assert_equal 1, fake_calendar.deleted_events.size
      end

      test "間違ったトークンでのキャンセルは 404" do
        freeze_base_time { post_reservation }

        post "/v1/public/reservations/deadbeef/cancel"

        assert_response :not_found
        assert_predicate Reservation.sole, :confirmed?
      end

      test "予約 POST のレートリミットが効く" do
        freeze_base_time do
          with_rack_attack do
            (Rack::Attack::RESERVATION_LIMIT + 1).times do |index|
              post_reservation(idempotency_key: "key-#{index}", start_at: jst(MONDAY, "10:00") + index.hours)
            end
          end
        end

        assert_response :too_many_requests
        assert_equal "RATE_LIMITED", response.parsed_body["code"]
        assert_predicate response.headers["Retry-After"], :present?
      end

      private

      def reservations_path
        "/v1/public/booking-types/#{@booking_type.slug}/reservations"
      end

      def json_headers(idempotency_key:, origin: BookingFactories::DEFAULT_ORIGIN)
        headers = { "Content-Type" => "application/json" }
        headers["Origin"] = origin if origin
        headers["Idempotency-Key"] = idempotency_key if idempotency_key
        headers
      end

      def post_reservation(idempotency_key: "key-default", origin: BookingFactories::DEFAULT_ORIGIN,
                           start_at: nil)
        post reservations_path,
             params: reservation_payload(start_at: start_at || @start_at).to_json,
             headers: json_headers(idempotency_key: idempotency_key, origin: origin)
      end

      # 応答の cancelUrl から生トークンを取り出す（DB にはハッシュしか無いため）
      def cancel_token_from_response
        response.parsed_body.fetch("cancelUrl").split("/").last
      end
    end
  end
end
