# frozen_string_literal: true

require "test_helper"

class BookingTypeTest < ActiveSupport::TestCase
  test "既定値で有効な予約メニューを作れる" do
    booking_type = create_booking_type

    assert booking_type.active?
    assert_equal 60, booking_type.duration_minutes
    assert_equal "Asia/Tokyo", booking_type.time_zone
    assert_equal 5, booking_type.weekly_availabilities.count
  end

  test "slug は英小文字・数字・ハイフンのみ" do
    %w[Genba genba_tsunagu genba.tsunagu -genba genba- ""].each do |slug|
      booking_type = BookingType.new(name: "無料相談", slug: slug)

      assert_predicate booking_type, :invalid?, "#{slug.inspect} が通ってしまった"
      assert booking_type.errors.of_kind?(:slug, :invalid) || booking_type.errors.of_kind?(:slug, :blank)
    end
  end

  test "slug は一意" do
    create_booking_type
    duplicate = BookingType.new(name: "別メニュー", slug: "genba-tsunagu-consultation")

    assert_predicate duplicate, :invalid?
    assert duplicate.errors.of_kind?(:slug, :taken)
  end

  test "不正なタイムゾーンは弾く" do
    booking_type = BookingType.new(name: "無料相談", slug: "x", time_zone: "Mars/Olympus")

    assert_predicate booking_type, :invalid?
    assert_includes booking_type.errors[:time_zone].join, "IANA"
  end

  test "duration_minutes は正の整数" do
    assert_predicate BookingType.new(name: "a", slug: "a", duration_minutes: 0), :invalid?
    assert_predicate BookingType.new(name: "a", slug: "a", duration_minutes: -30), :invalid?
  end

  test "booking_calendar_id はメニュー指定を優先し、無ければ環境変数の既定値を使う" do
    with_calendar = create_booking_type(google_booking_calendar_id: "menu@example.com")
    assert_equal "menu@example.com", with_calendar.booking_calendar_id

    without_calendar = create_booking_type(slug: "other", google_booking_calendar_id: nil)
    assert_equal SlotRelayTestConfig::BOOKING_CALENDAR_ID, without_calendar.booking_calendar_id
  end

  test "予約が存在する予約メニューは削除できない" do
    booking_type = create_booking_type
    create_confirmed_reservation(booking_type: booking_type, start_at: jst(MONDAY, "10:00"))

    assert_not booking_type.destroy
    assert_predicate BookingType.where(id: booking_type.id), :exists?
  end

  test "予約メニューを削除すると受付時間と許可 Origin も消える" do
    booking_type = create_booking_type

    assert_difference "WeeklyAvailability.count", -5 do
      assert_difference "BookingTypeOrigin.count", -1 do
        assert booking_type.destroy
      end
    end
  end
end
