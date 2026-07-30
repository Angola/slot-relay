# frozen_string_literal: true

# テストデータの生成ヘルパー。fixtures を使わないのは、
# 空き枠計算のテストが「現在時刻からの相対日付」に強く依存するため。
module BookingFactories
  DEFAULT_ORIGIN = "https://genba-tsunagu.jp"

  # テストの基準時刻。2026-07-30 は木曜、2026-08-03 は月曜。
  # 最短受付時間 1440 分（24 時間）を足しても月曜の枠はすべて予約可能な位置にある。
  BASE_TIME = ActiveSupport::TimeZone["Asia/Tokyo"].local(2026, 7, 30, 9, 0)
  MONDAY = Date.new(2026, 8, 3)
  SATURDAY = Date.new(2026, 8, 1)

  # 平日 10:00-18:00 / 60 分枠 / 前日までに予約 の予約メニュー
  def create_booking_type(**overrides)
    weekly = overrides.delete(:weekly) || (1..5).map { |day| { day_of_week: day, start_time: "10:00", end_time: "18:00" } }
    origins = overrides.delete(:origins) || [DEFAULT_ORIGIN]

    booking_type = BookingType.create!(
      {
        name: "無料相談",
        slug: "genba-tsunagu-consultation",
        duration_minutes: 60,
        time_zone: "Asia/Tokyo",
        minimum_notice_minutes: 1440,
        booking_window_days: 30,
        google_booking_calendar_id: SlotRelayTestConfig::BOOKING_CALENDAR_ID
      }.merge(overrides)
    )

    weekly.each { |attrs| booking_type.weekly_availabilities.create!(attrs) }
    origins.each { |origin| booking_type.origins.create!(origin: origin) }
    OriginAllowList.reset!

    booking_type.reload
  end

  # 予約メニューのタイムゾーンでの指定時刻を返す。
  def jst(date, hhmm)
    hour, minute = hhmm.split(":").map(&:to_i)
    ActiveSupport::TimeZone["Asia/Tokyo"].local(date.year, date.month, date.day, hour, minute)
  end

  # 基準時刻を固定して実行する。空き枠計算は「いま」に強く依存するため必須。
  def freeze_base_time(&block)
    travel_to(BASE_TIME, &block)
  end

  def create_confirmed_reservation(booking_type:, start_at:, **overrides)
    reservation = booking_type.reservations.new(
      {
        start_at: start_at,
        end_at: start_at + booking_type.duration_minutes.minutes,
        guest_name: "山田太郎",
        guest_email: "taro@example.com",
        guest_company: "株式会社サンプル",
        status: "confirmed",
        google_event_id: "existing-event"
      }.merge(overrides)
    )
    reservation.issue_cancel_token!
    reservation.save!
    reservation
  end

  def reservation_payload(start_at:, **overrides)
    {
      startAt: start_at.iso8601,
      guest: {
        name: "山田太郎",
        email: "taro@example.com",
        company: "株式会社サンプル",
        phone: "090-0000-0000"
      },
      answers: { "相談内容" => "日報業務を自動化したい" }
    }.merge(overrides)
  end
end
