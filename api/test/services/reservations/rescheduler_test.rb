# frozen_string_literal: true

require "test_helper"

module Reservations
  class ReschedulerTest < ActiveSupport::TestCase
    MONDAY = BookingFactories::MONDAY

    setup do
      @booking_type = create_booking_type
      @reservation = create_confirmed_reservation(booking_type: @booking_type, start_at: jst(MONDAY, "10:00"))
    end

    test "日時を変更し、新しい Google 予定を作って古い予定を消す" do
      freeze_base_time do
        result = reschedule(jst(MONDAY, "14:00"))

        assert_predicate result, :success?
        @reservation.reload

        assert_equal jst(MONDAY, "14:00"), @reservation.start_at
        assert_equal jst(MONDAY, "15:00"), @reservation.end_at

        assert_equal 1, fake_calendar.created_events.size
        assert_equal @reservation.google_event_id, fake_calendar.created_events.first[:id]
        assert_equal ["existing-event"], fake_calendar.deleted_events.map { |e| e[:event_id] }
      end
    end

    test "変更を予約者へ通知する" do
      freeze_base_time do
        reschedule(jst(MONDAY, "14:00"))

        mail = ActionMailer::Base.deliveries.last

        assert_equal ["taro@example.com"], mail.to
        assert_includes mail.subject, "日時を変更"
        assert_includes mail.body.to_s, "2026年8月3日(月) 14:00"
      end
    end

    test "変更先が埋まっていれば元の日時を保つ" do
      freeze_base_time do
        create_confirmed_reservation(
          booking_type: @booking_type, start_at: jst(MONDAY, "14:00"), guest_email: "other@example.com"
        )

        result = reschedule(jst(MONDAY, "14:00"))

        assert_predicate result, :failure?
        assert_equal :slot_unavailable, result.code
        assert_equal jst(MONDAY, "10:00"), @reservation.reload.start_at
        assert_empty fake_calendar.created_events
      end
    end

    test "Google カレンダーに予定がある時間へは変更できない" do
      fake_calendar.add_busy(SlotRelayTestConfig::BUSY_CALENDAR_ID,
                             [[jst(MONDAY, "14:00"), jst(MONDAY, "15:00")]])

      freeze_base_time do
        result = reschedule(jst(MONDAY, "14:00"))

        assert_predicate result, :failure?
        assert_equal :slot_unavailable, result.code
        assert_equal jst(MONDAY, "10:00"), @reservation.reload.start_at
      end
    end

    test "受付時間外へは変更できない" do
      freeze_base_time do
        result = reschedule(jst(MONDAY, "21:00"))

        assert_predicate result, :failure?
        assert_equal :slot_unavailable, result.code
        assert_equal jst(MONDAY, "10:00"), @reservation.reload.start_at
      end
    end

    test "Google 予定の作成に失敗したら元の日時・予定 ID へ戻す" do
      fake_calendar.raise_on_create = true

      freeze_base_time do
        result = reschedule(jst(MONDAY, "14:00"))

        assert_predicate result, :failure?
        assert_equal :calendar_error, result.code

        @reservation.reload
        assert_equal jst(MONDAY, "10:00"), @reservation.start_at
        assert_equal "existing-event", @reservation.google_event_id
      end
    end

    test "startAt の形式が不正なら 422" do
      freeze_base_time do
        result = reschedule("not-a-time")

        assert_predicate result, :failure?
        assert_equal :invalid_start_at, result.code
      end
    end

    test "確定済み以外は変更できない" do
      @reservation.update_columns(status: "cancelled")

      freeze_base_time do
        result = reschedule(jst(MONDAY, "14:00"))

        assert_predicate result, :failure?
        assert_equal :not_reschedulable, result.code
      end
    end

    private

    def reschedule(start_at)
      value = start_at.is_a?(String) ? start_at : start_at.iso8601
      Rescheduler.new(reservation: @reservation, start_at: value, calendar_client: fake_calendar).call
    end
  end
end
