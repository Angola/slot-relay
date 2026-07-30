# frozen_string_literal: true

require "test_helper"

class AvailabilityCalculatorTest < ActiveSupport::TestCase
  MONDAY = BookingFactories::MONDAY
  SATURDAY = BookingFactories::SATURDAY

  setup { @booking_type = create_booking_type }

  test "曜日別受付時間から 60 分刻みの枠を生成する" do
    freeze_base_time do
      slots = slots_on(MONDAY)

      assert_equal 8, slots.size
      assert_equal jst(MONDAY, "10:00"), slots.first.start_at
      assert_equal jst(MONDAY, "11:00"), slots.first.end_at
      assert_equal jst(MONDAY, "17:00"), slots.last.start_at
      assert_equal jst(MONDAY, "18:00"), slots.last.end_at
    end
  end

  test "受付時間に収まらない端の枠は作らない" do
    booking_type = create_booking_type(slug: "ninety", duration_minutes: 90,
                                       weekly: [{ day_of_week: 1, start_time: "10:00", end_time: "14:00" }])

    freeze_base_time do
      slots = slots_on(MONDAY, booking_type: booking_type)

      # 10:00-11:30 / 11:30-13:00 の 2 枠。13:00-14:30 は 14:00 を越えるため作らない
      assert_equal 2, slots.size
      assert_equal jst(MONDAY, "13:00"), slots.last.end_at
    end
  end

  test "受付時間が設定されていない曜日は枠が 0 件（ただし日自体は返る）" do
    freeze_base_time do
      day = days_between(SATURDAY, SATURDAY).first

      assert_equal SATURDAY, day.date
      assert_empty day.slots
    end
  end

  test "特定日を休業にすると枠が消える" do
    @booking_type.availability_overrides.create!(date: MONDAY, is_available: false)

    freeze_base_time do
      assert_empty slots_on(MONDAY)
    end
  end

  test "特定日の受付時間を差し替えると曜日別設定を完全に置き換える" do
    @booking_type.availability_overrides.create!(date: MONDAY, is_available: true,
                                                 start_time: "13:00", end_time: "15:00")

    freeze_base_time do
      slots = slots_on(MONDAY)

      assert_equal 2, slots.size
      assert_equal jst(MONDAY, "13:00"), slots.first.start_at
      assert_equal jst(MONDAY, "15:00"), slots.last.end_at
    end
  end

  test "土曜を営業日に変えるオーバーライドも効く" do
    @booking_type.availability_overrides.create!(date: SATURDAY, is_available: true,
                                                 start_time: "10:00", end_time: "12:00")

    freeze_base_time do
      assert_equal 2, slots_on(SATURDAY).size
    end
  end

  test "最短受付時間より前の枠は返さない" do
    # 基準時刻 7/30 09:00 JST + 1440 分 = 7/31 09:00 JST
    friday = Date.new(2026, 7, 31)

    freeze_base_time do
      slots = slots_on(friday)

      assert_equal jst(friday, "10:00"), slots.first.start_at
      assert(slots.all? { |slot| slot.start_at >= BookingFactories::BASE_TIME + 1440.minutes })
    end
  end

  test "最短受付時間が長いと当日・翌日の枠が消える" do
    booking_type = create_booking_type(slug: "long-notice", minimum_notice_minutes: 7 * 24 * 60)

    freeze_base_time do
      assert_empty slots_on(MONDAY, booking_type: booking_type) # 7/30 + 7 日 = 8/6 より前
      assert_predicate slots_on(Date.new(2026, 8, 7), booking_type: booking_type), :any?
    end
  end

  test "最大予約可能日を越える日は返さない" do
    booking_type = create_booking_type(slug: "short-window", booking_window_days: 3)

    freeze_base_time do
      # 基準日 7/30 + 3 日 = 8/2 まで。月曜 8/3 は範囲外
      days = days_between(MONDAY, MONDAY, booking_type: booking_type)

      assert_empty days
    end
  end

  test "過去の日付は返さない" do
    freeze_base_time do
      days = days_between(Date.new(2026, 7, 20), Date.new(2026, 7, 30))

      assert_equal Date.new(2026, 7, 30), days.first.date
    end
  end

  test "Google カレンダーに予定がある枠は返さない" do
    fake_calendar.add_busy(SlotRelayTestConfig::BUSY_CALENDAR_ID,
                           [[jst(MONDAY, "11:00"), jst(MONDAY, "12:00")]])

    freeze_base_time do
      starts = slots_on(MONDAY).map(&:start_at)

      assert_not_includes starts, jst(MONDAY, "11:00")
      assert_includes starts, jst(MONDAY, "10:00")
      assert_includes starts, jst(MONDAY, "12:00")
    end
  end

  test "Busy 時間が枠に一部でも重なれば除外する" do
    fake_calendar.add_busy(SlotRelayTestConfig::BUSY_CALENDAR_ID,
                           [[jst(MONDAY, "10:30"), jst(MONDAY, "10:45")]])

    freeze_base_time do
      assert_not_includes slots_on(MONDAY).map(&:start_at), jst(MONDAY, "10:00")
    end
  end

  test "予定の終了時刻と枠の開始時刻が同じなら重なりではない" do
    fake_calendar.add_busy(SlotRelayTestConfig::BUSY_CALENDAR_ID,
                           [[jst(MONDAY, "09:00"), jst(MONDAY, "10:00")]])

    freeze_base_time do
      assert_includes slots_on(MONDAY).map(&:start_at), jst(MONDAY, "10:00")
    end
  end

  test "登録先カレンダーも空き判定に含める" do
    fake_calendar.add_busy(SlotRelayTestConfig::BOOKING_CALENDAR_ID,
                           [[jst(MONDAY, "14:00"), jst(MONDAY, "15:00")]])

    freeze_base_time do
      assert_not_includes slots_on(MONDAY).map(&:start_at), jst(MONDAY, "14:00")
    end
  end

  test "前後バッファぶん離れていない枠は除外する" do
    booking_type = create_booking_type(slug: "buffered", buffer_before_minutes: 30, buffer_after_minutes: 30)
    fake_calendar.add_busy(SlotRelayTestConfig::BUSY_CALENDAR_ID,
                           [[jst(MONDAY, "12:00"), jst(MONDAY, "12:15")]])

    freeze_base_time do
      starts = slots_on(MONDAY, booking_type: booking_type).map(&:start_at)

      # 11:00-12:00 の枠は終了後 30 分（〜12:30）が塞がれるため不可
      assert_not_includes starts, jst(MONDAY, "11:00")
      # 12:00-13:00 は Busy と直接重なるため不可
      assert_not_includes starts, jst(MONDAY, "12:00")
      # 13:00-14:00 は開始前 30 分（12:30〜）が空いているため可
      assert_includes starts, jst(MONDAY, "13:00")
      assert_includes starts, jst(MONDAY, "10:00")
    end
  end

  test "確定済みの予約と重なる枠は返さない" do
    freeze_base_time do
      create_confirmed_reservation(booking_type: @booking_type, start_at: jst(MONDAY, "15:00"))

      assert_not_includes slots_on(MONDAY).map(&:start_at), jst(MONDAY, "15:00")
    end
  end

  test "期限内の pending 予約は枠を塞ぐが、期限切れは塞がない" do
    freeze_base_time do
      @booking_type.reservations.create!(
        start_at: jst(MONDAY, "10:00"), end_at: jst(MONDAY, "11:00"),
        guest_name: "仮", guest_email: "a@example.com",
        status: "pending", expires_at: 3.minutes.from_now
      )
      @booking_type.reservations.create!(
        start_at: jst(MONDAY, "12:00"), end_at: jst(MONDAY, "13:00"),
        guest_name: "期限切れ", guest_email: "b@example.com",
        status: "pending", expires_at: 1.minute.ago
      )

      starts = slots_on(MONDAY).map(&:start_at)

      assert_not_includes starts, jst(MONDAY, "10:00")
      assert_includes starts, jst(MONDAY, "12:00")
    end
  end

  test "exclude_reservation_id で自分の仮確保を無視できる" do
    freeze_base_time do
      pending = @booking_type.reservations.create!(
        start_at: jst(MONDAY, "10:00"), end_at: jst(MONDAY, "11:00"),
        guest_name: "仮", guest_email: "a@example.com",
        status: "pending", expires_at: 3.minutes.from_now
      )

      calculator = AvailabilityCalculator.new(
        booking_type: @booking_type, from: MONDAY, to: MONDAY,
        exclude_reservation_id: pending.id, calendar_client: fake_calendar
      )

      assert calculator.slot_available?(jst(MONDAY, "10:00"))
    end
  end

  test "キャンセル済み予約は枠を塞がない" do
    freeze_base_time do
      reservation = create_confirmed_reservation(booking_type: @booking_type, start_at: jst(MONDAY, "16:00"))
      reservation.update!(status: "cancelled", cancelled_at: Time.current)

      assert_includes slots_on(MONDAY).map(&:start_at), jst(MONDAY, "16:00")
    end
  end

  test "枠が 0 件の日も含めて期間内のすべての日を返す" do
    freeze_base_time do
      days = days_between(SATURDAY, Date.new(2026, 8, 4))

      assert_equal [SATURDAY, Date.new(2026, 8, 2), MONDAY, Date.new(2026, 8, 4)], days.map(&:date)
      assert_empty days[0].slots # 土
      assert_empty days[1].slots # 日
      assert_equal 8, days[2].slots.size
    end
  end

  test "期間が長すぎるとエラー" do
    freeze_base_time do
      assert_raises(AvailabilityCalculator::RangeTooWide) do
        days_between(Date.new(2026, 8, 1), Date.new(2026, 10, 31))
      end
    end
  end

  test "slot_available? は枠の境界に一致しない時刻を拒否する" do
    freeze_base_time do
      calculator = AvailabilityCalculator.new(
        booking_type: @booking_type, from: MONDAY, to: MONDAY, calendar_client: fake_calendar
      )

      assert calculator.slot_available?(jst(MONDAY, "10:00"))
      assert_not calculator.slot_available?(jst(MONDAY, "10:30"))
      assert_not calculator.slot_available?(jst(MONDAY, "09:00"))
      assert_not calculator.slot_available?(jst(SATURDAY, "10:00"))
    end
  end

  test "FreeBusy の取得範囲はバッファを含む" do
    booking_type = create_booking_type(slug: "buffered2", buffer_before_minutes: 30, buffer_after_minutes: 45)

    freeze_base_time do
      slots_on(MONDAY, booking_type: booking_type)

      query = fake_calendar.freebusy_queries.last

      assert_equal jst(MONDAY, "09:30"), query[:time_min]
      assert_equal jst(MONDAY, "18:45"), query[:time_max]
    end
  end

  test "Busy 時間を取得できない場合は例外を伝播させる（空き扱いにしない）" do
    fake_calendar.raise_on_busy = true

    freeze_base_time do
      assert_raises(GoogleCalendar::Client::Error) { slots_on(MONDAY) }
    end
  end

  private

  def days_between(from, to, booking_type: @booking_type)
    AvailabilityCalculator.new(
      booking_type: booking_type, from: from, to: to, calendar_client: fake_calendar
    ).call
  end

  def slots_on(date, booking_type: @booking_type)
    days_between(date, date, booking_type: booking_type).first&.slots || []
  end
end
