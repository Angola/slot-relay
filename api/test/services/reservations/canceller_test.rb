# frozen_string_literal: true

require "test_helper"

module Reservations
  class CancellerTest < ActiveSupport::TestCase
    MONDAY = BookingFactories::MONDAY

    setup do
      @booking_type = create_booking_type
      @reservation = create_confirmed_reservation(booking_type: @booking_type, start_at: jst(MONDAY, "10:00"))
    end

    test "予約をキャンセルし Google 予定も削除する" do
      result = cancel

      assert_predicate result, :success?
      assert_predicate @reservation.reload, :cancelled?
      assert_predicate @reservation.cancelled_at, :present?

      assert_equal 1, fake_calendar.deleted_events.size
      assert_equal "existing-event", fake_calendar.deleted_events.first[:event_id]
      assert_equal SlotRelayTestConfig::BOOKING_CALENDAR_ID, fake_calendar.deleted_events.first[:calendar_id]
    end

    test "予約者と管理者へキャンセル通知を送る" do
      cancel

      assert_equal 2, ActionMailer::Base.deliveries.size
      assert_includes ActionMailer::Base.deliveries.first.subject, "キャンセル"
      assert_equal ["taro@example.com"], ActionMailer::Base.deliveries.first.to
      assert_equal ["admin@example.com"], ActionMailer::Base.deliveries.second.to
    end

    test "キャンセル後は同じ枠を再度予約できる" do
      cancel

      freeze_base_time do
        calculator = AvailabilityCalculator.new(
          booking_type: @booking_type, from: MONDAY, to: MONDAY, calendar_client: fake_calendar
        )

        assert calculator.slot_available?(jst(MONDAY, "10:00"))
      end
    end

    test "すでにキャンセル済みなら何もせず成功する（冪等）" do
      cancel
      ActionMailer::Base.deliveries.clear

      result = cancel

      assert_predicate result, :success?
      assert_equal 1, fake_calendar.deleted_events.size
      assert_empty ActionMailer::Base.deliveries
    end

    test "pending / failed はキャンセルできない" do
      %w[pending failed].each do |status|
        @reservation.update_columns(status: status)

        result = cancel

        assert_predicate result, :failure?
        assert_equal :not_cancellable, result.code
      end
    end

    test "Google 予定の削除に失敗しても DB のキャンセルは確定させる" do
      fake_calendar.raise_on_delete = true

      result = cancel

      assert_predicate result, :success?
      assert_predicate @reservation.reload, :cancelled?

      # 予約者・管理者へのキャンセル通知に加えて、管理者へエラー通知が飛ぶ
      subjects = ActionMailer::Base.deliveries.map(&:subject)
      assert(subjects.any? { |subject| subject.include?("[要対応]") })
    end

    test "Google 予定 ID が無い予約でもキャンセルできる" do
      @reservation.update!(google_event_id: nil)

      result = cancel

      assert_predicate result, :success?
      assert_empty fake_calendar.deleted_events
    end

    private

    def cancel
      Canceller.new(reservation: @reservation, calendar_client: fake_calendar).call
    end
  end
end
