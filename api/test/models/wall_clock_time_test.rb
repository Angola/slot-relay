# frozen_string_literal: true

require "test_helper"

# 壁時計時刻（time カラム）の扱い。WeeklyAvailability を代表として検証する。
class WallClockTimeTest < ActiveSupport::TestCase
  setup { @booking_type = create_booking_type(weekly: []) }

  test '"HH:MM" を受け取り分数と "HH:MM" で読み出せる' do
    record = @booking_type.weekly_availabilities.create!(day_of_week: 1, start_time: "10:00", end_time: "18:30")

    assert_equal 600, record.start_time_minutes
    assert_equal 1_110, record.end_time_minutes
    assert_equal "10:00", record.start_time_hhmm
    assert_equal "18:30", record.end_time_hhmm
    assert_equal 600, record.start_minutes
    assert_equal 1_110, record.end_minutes
  end

  # 回帰テスト: time カラムがタイムゾーン変換されると 10:00 が 19:00 として読まれ、
  # 空き枠が丸ごと消える。読み出し時の Time.zone に依存しないことを保証する。
  test "読み出し時の Time.zone に影響されない" do
    @booking_type.weekly_availabilities.create!(day_of_week: 1, start_time: "10:00", end_time: "18:00")
    record = WeeklyAvailability.find_by!(booking_type: @booking_type, day_of_week: 1)

    ["UTC", "Asia/Tokyo", "America/Los_Angeles"].each do |zone|
      Time.use_zone(zone) do
        reloaded = WeeklyAvailability.find(record.id)

        assert_equal 600, reloaded.start_time_minutes, "Time.zone=#{zone} でずれた"
        assert_equal 1_080, reloaded.end_time_minutes, "Time.zone=#{zone} でずれた"
      end
    end
  end

  test '"HH:MM:SS" も受け付ける' do
    record = @booking_type.weekly_availabilities.create!(day_of_week: 1, start_time: "09:15:00", end_time: "17:45:00")

    assert_equal "09:15", record.start_time_hhmm
    assert_equal "17:45", record.end_time_hhmm
  end

  test "壊れた時刻文字列は 00:00 へ丸めずエラーにする" do
    ["25:00", "10:60", "abc", "10", "1000", "-1:00"].each do |value|
      record = @booking_type.weekly_availabilities.new(day_of_week: 1, start_time: value, end_time: "18:00")

      assert_predicate record, :invalid?, "#{value.inspect} が通ってしまった"
      assert record.errors.of_kind?(:start_time, :blank)
    end
  end

  test "終了が開始より前・同じならエラー" do
    ["10:00", "09:00"].each do |end_time|
      record = @booking_type.weekly_availabilities.new(day_of_week: 1, start_time: "10:00", end_time: end_time)

      assert_predicate record, :invalid?
      assert_predicate record.errors[:end_time], :any?
    end
  end

  test "曜日は 0〜6" do
    [-1, 7, 99].each do |day|
      record = @booking_type.weekly_availabilities.new(day_of_week: day, start_time: "10:00", end_time: "18:00")

      assert_predicate record, :invalid?
    end
  end

  test "特定日オーバーライドは is_available=true のとき時刻が必須" do
    record = @booking_type.availability_overrides.new(date: Date.new(2026, 8, 13), is_available: true)

    assert_predicate record, :invalid?
    assert_predicate record.errors[:start_time], :any?
  end

  test "休業指定（is_available=false）は時刻なしでよい" do
    record = @booking_type.availability_overrides.new(date: Date.new(2026, 8, 13), is_available: false)

    assert_predicate record, :valid?
  end
end
