# frozen_string_literal: true

# ローカル開発用の予約メニュー。本番では管理 API から登録する（docs/DEPLOY.md）。
#
#   bin/rails db:seed

booking_type = BookingType.find_or_initialize_by(slug: "genba-tsunagu-consultation")
booking_type.update!(
  name: "無料相談",
  description: "業務自動化についての無料相談（60 分）",
  duration_minutes: 60,
  time_zone: "Asia/Tokyo",
  minimum_notice_minutes: 1_440,
  booking_window_days: 30,
  # 予約は登録先カレンダーごとに直列化される（排他制約のスコープ）。
  # ローカルでは Google に繋がないが、値は必須なのでプレースホルダを入れる。
  google_booking_calendar_id: ENV.fetch("GOOGLE_BOOKING_CALENDAR_ID", "local-dev-booking-calendar"),
  status: "active"
)

# 参照実装 UI のオリジン。compose はポート衝突を避けて 3000 以外で起動することがあるため、
# DEV_ALLOWED_ORIGINS で上書きできるようにしておく（compose.yaml が渡す）。
dev_origins = ENV.fetch("DEV_ALLOWED_ORIGINS", "http://localhost:3000")
                 .split(",").map(&:strip).reject(&:blank?)

(dev_origins + %w[http://localhost:3000 https://genba-tsunagu.jp]).uniq.each do |origin|
  booking_type.origins.find_or_create_by!(origin: origin)
end

# 平日 12:00〜19:00。60 分枠なので 12:00 / 13:00 / … / 18:00 の 7 枠になる。
# 終了を 19:00 にしているのは、枠の終わりが受付終了を超えない仕様のため
# （18:00 開始の枠は 19:00 に終わる。AvailabilityCalculator#slots_in_window）。
booking_type.weekly_availabilities.destroy_all
(1..5).each do |day_of_week|
  booking_type.weekly_availabilities.create!(day_of_week: day_of_week, start_time: "12:00", end_time: "19:00")
end

puts "予約メニュー #{booking_type.slug} を作成しました（許可 Origin: #{booking_type.allowed_origins.join(", ")}）"
