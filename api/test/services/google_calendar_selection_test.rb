# frozen_string_literal: true

require "test_helper"

class GoogleCalendarSelectionTest < ActiveSupport::TestCase
  setup do
    @booking_type = create_booking_type
  end

  test "登録先と空き判定のカレンダーを保存する" do
    result = GoogleCalendarSelection.new(
      @booking_type.id => {
        booking_calendar_id: "booking@example.com",
        busy_calendar_ids: %w[owner@example.com holiday@example.com]
      }
    ).call

    assert result.success?
    @booking_type.reload
    assert_equal "booking@example.com", @booking_type.google_booking_calendar_id
    assert_equal %w[owner@example.com holiday@example.com], @booking_type.google_busy_calendar_ids
  end

  test "重複した ID は 1 つにまとめる" do
    GoogleCalendarSelection.new(
      @booking_type.id => { booking_calendar_id: nil, busy_calendar_ids: %w[a@example.com a@example.com] }
    ).call

    assert_equal %w[a@example.com], @booking_type.reload.google_busy_calendar_ids
  end

  test "存在しない予約メニューは失敗させ、他のメニューも更新しない" do
    result = GoogleCalendarSelection.new(
      @booking_type.id => { booking_calendar_id: "changed@example.com", busy_calendar_ids: [] },
      999_999 => { booking_calendar_id: "x@example.com", busy_calendar_ids: [] }
    ).call

    assert result.failure?
    assert_equal :not_found, result.code
    assert_equal SlotRelayTestConfig::BOOKING_CALENDAR_ID, @booking_type.reload.google_booking_calendar_id
  end

  test "空の入力は何もしない" do
    result = GoogleCalendarSelection.new({}).call

    assert result.success?
    assert_empty result.value
  end

  test "複数メニューをまとめて更新できる" do
    other = create_booking_type(slug: "another-menu", name: "別メニュー", origins: [])

    result = GoogleCalendarSelection.new(
      @booking_type.id => { booking_calendar_id: "a@example.com", busy_calendar_ids: [] },
      other.id => { booking_calendar_id: "b@example.com", busy_calendar_ids: %w[c@example.com] }
    ).call

    assert result.success?
    assert_equal "a@example.com", @booking_type.reload.google_booking_calendar_id
    assert_equal "b@example.com", other.reload.google_booking_calendar_id
    assert_equal %w[c@example.com], other.google_busy_calendar_ids
  end
end
