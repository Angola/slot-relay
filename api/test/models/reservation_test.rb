# frozen_string_literal: true

require "test_helper"

class ReservationTest < ActiveSupport::TestCase
  setup do
    @booking_type = create_booking_type
    @start_at = jst(BookingFactories::MONDAY, "10:00")
  end

  test "public_id は自動採番される" do
    reservation = create_confirmed_reservation(booking_type: @booking_type, start_at: @start_at)

    assert_match(/\Ares_[A-Za-z0-9]+\z/, reservation.public_id)
  end

  test "キャンセルトークンはハッシュだけを保存する" do
    reservation = create_confirmed_reservation(booking_type: @booking_type, start_at: @start_at)
    token = reservation.cancel_token

    assert_predicate token, :present?
    assert_not_equal token, reservation.cancel_token_hash
    assert_equal OpenSSL::Digest::SHA256.hexdigest(token), reservation.cancel_token_hash

    # 保存済みのレコードからは生トークンを復元できない
    assert_nil Reservation.find(reservation.id).cancel_token
  end

  test "生トークンから予約を引ける／間違ったトークンでは引けない" do
    reservation = create_confirmed_reservation(booking_type: @booking_type, start_at: @start_at)

    assert_equal reservation, Reservation.find_by_cancel_token(reservation.cancel_token)
    assert_nil Reservation.find_by_cancel_token("wrong-token")
    assert_nil Reservation.find_by_cancel_token(nil)
    assert_nil Reservation.find_by_cancel_token("")
  end

  test "メールアドレスの形式を検証する" do
    reservation = @booking_type.reservations.new(
      start_at: @start_at, end_at: @start_at + 1.hour,
      guest_name: "山田太郎", guest_email: "not-an-email"
    )

    assert_predicate reservation, :invalid?
    assert_predicate reservation.errors[:guest_email], :any?
  end

  test "answers はキー数と値の長さを制限する" do
    too_many = @booking_type.reservations.new(
      start_at: @start_at, end_at: @start_at + 1.hour,
      guest_name: "山田太郎", guest_email: "a@example.com",
      answers: (1..31).to_h { |i| ["q#{i}", "a"] }
    )
    assert_predicate too_many, :invalid?
    assert_includes too_many.errors[:answers].join, "項目数"

    too_long = @booking_type.reservations.new(
      start_at: @start_at, end_at: @start_at + 1.hour,
      guest_name: "山田太郎", guest_email: "a@example.com",
      answers: { "q" => "a" * 2_001 }
    )
    assert_predicate too_long, :invalid?
    assert_includes too_long.errors[:answers].join, "長すぎます"
  end

  test "blocking スコープは confirmed と期限内 pending だけを含む" do
    freeze_base_time do
      confirmed = create_confirmed_reservation(booking_type: @booking_type, start_at: @start_at)
      live_pending = build_pending(jst(BookingFactories::MONDAY, "11:00"), expires_at: 3.minutes.from_now)
      expired_pending = build_pending(jst(BookingFactories::MONDAY, "12:00"), expires_at: 1.minute.ago)
      cancelled = build_reservation(jst(BookingFactories::MONDAY, "13:00"), status: "cancelled")
      failed = build_reservation(jst(BookingFactories::MONDAY, "14:00"), status: "failed")

      blocking = @booking_type.reservations.blocking(Time.current)

      assert_includes blocking, confirmed
      assert_includes blocking, live_pending
      assert_not_includes blocking, expired_pending
      assert_not_includes blocking, cancelled
      assert_not_includes blocking, failed
    end
  end

  test "同じ枠に有効な予約を 2 件作れない（DB の排他制約）" do
    create_confirmed_reservation(booking_type: @booking_type, start_at: @start_at)

    error = assert_raises(ActiveRecord::StatementInvalid) do
      create_confirmed_reservation(booking_type: @booking_type, start_at: @start_at, guest_email: "b@example.com")
    end

    assert_kind_of PG::ExclusionViolation, error.cause
  end

  test "一部でも時間が重なれば排他制約に触れる" do
    create_confirmed_reservation(booking_type: @booking_type, start_at: jst(BookingFactories::MONDAY, "10:00"))

    assert_raises(ActiveRecord::StatementInvalid) do
      @booking_type.reservations.create!(
        start_at: jst(BookingFactories::MONDAY, "10:30"),
        end_at: jst(BookingFactories::MONDAY, "11:30"),
        guest_name: "別の人", guest_email: "b@example.com", status: "confirmed"
      )
    end
  end

  test "隣接する枠（終了時刻＝開始時刻）は重なりとみなさない" do
    create_confirmed_reservation(booking_type: @booking_type, start_at: jst(BookingFactories::MONDAY, "10:00"))

    assert_nothing_raised do
      create_confirmed_reservation(
        booking_type: @booking_type,
        start_at: jst(BookingFactories::MONDAY, "11:00"),
        guest_email: "b@example.com"
      )
    end
  end

  test "cancelled / failed は枠を塞がない" do
    reservation = create_confirmed_reservation(booking_type: @booking_type, start_at: @start_at)
    reservation.update!(status: "cancelled", cancelled_at: Time.current)

    assert_nothing_raised do
      create_confirmed_reservation(booking_type: @booking_type, start_at: @start_at, guest_email: "b@example.com")
    end
  end

  test "登録先カレンダーが違えば別メニューで同じ時間を予約できる" do
    other = create_booking_type(slug: "other-consultation", google_booking_calendar_id: "other@example.com")
    create_confirmed_reservation(booking_type: @booking_type, start_at: @start_at)

    assert_nothing_raised do
      create_confirmed_reservation(booking_type: other, start_at: @start_at)
    end
  end

  # 排他制約を booking_type_id ではなく booking_calendar_id でスコープしていることの回帰テスト。
  # 予約メニューは既定で同じ登録先カレンダーを共有するため、メニュー単位のスコープだと
  # 「別メニュー・同じカレンダー・同じ時刻」がすり抜けて 1 つのカレンダーが二重予約になる。
  test "登録先カレンダーが同じなら別メニューでも同じ時間は予約できない" do
    other = create_booking_type(slug: "other-consultation")
    assert_equal @booking_type.booking_calendar_id, other.booking_calendar_id

    create_confirmed_reservation(booking_type: @booking_type, start_at: @start_at)

    error = assert_raises(ActiveRecord::StatementInvalid) do
      create_confirmed_reservation(booking_type: other, start_at: @start_at, guest_email: "b@example.com")
    end

    assert_kind_of PG::ExclusionViolation, error.cause
  end

  test "登録先カレンダーが同じなら別メニューの pending も枠を塞ぐ" do
    other = create_booking_type(slug: "other-consultation")

    freeze_base_time do
      other.reservations.create!(
        start_at: @start_at, end_at: @start_at + 1.hour,
        guest_name: "別メニューの仮確保", guest_email: "a@example.com",
        status: "pending", expires_at: 3.minutes.from_now
      )

      calculator = AvailabilityCalculator.new(
        booking_type: @booking_type, from: BookingFactories::MONDAY, to: BookingFactories::MONDAY,
        calendar_client: FakeCalendarClient.new
      )

      assert_not calculator.slot_available?(@start_at)
    end
  end

  test "登録先カレンダーは予約時点の値で固定される" do
    reservation = create_confirmed_reservation(booking_type: @booking_type, start_at: @start_at)
    assert_equal SlotRelayTestConfig::BOOKING_CALENDAR_ID, reservation.booking_calendar_id

    @booking_type.update!(google_booking_calendar_id: "moved@example.com")

    assert_equal SlotRelayTestConfig::BOOKING_CALENDAR_ID, reservation.reload.booking_calendar_id
  end

  test "登録先カレンダーが決まらない予約は作れない" do
    booking_type = create_booking_type(slug: "no-calendar", google_booking_calendar_id: nil)
    configure_slot_relay!(google_booking_calendar_id: nil)

    reservation = booking_type.reservations.new(
      start_at: @start_at, end_at: @start_at + 1.hour,
      guest_name: "山田太郎", guest_email: "taro@example.com"
    )

    assert_predicate reservation, :invalid?
    assert_predicate reservation.errors[:booking_calendar_id], :any?
  end

  private

  def build_pending(start_at, expires_at:)
    build_reservation(start_at, status: "pending", expires_at: expires_at)
  end

  def build_reservation(start_at, **overrides)
    @booking_type.reservations.create!(
      {
        start_at: start_at,
        end_at: start_at + 1.hour,
        guest_name: "山田太郎",
        guest_email: "taro@example.com"
      }.merge(overrides)
    )
  end
end
