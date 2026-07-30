# frozen_string_literal: true

# テスト中の SlotRelay.config を固定する。ENV に依存させないことで、
# 実行環境の環境変数でテスト結果が変わるのを防ぐ。
module SlotRelayTestConfig
  ADMIN_API_KEY = "test-admin-key-0123456789abcdef0123456789abcdef"
  BUSY_CALENDAR_ID = "busy@example.com"
  BOOKING_CALENDAR_ID = "booking@example.com"

  def configure_slot_relay!(**overrides)
    SlotRelay.config = SlotRelay::Configuration.new(
      **{
        admin_api_key: ADMIN_API_KEY,
        google_service_account_email: "slot-relay@example.iam.gserviceaccount.com",
        google_service_account_private_key: "-----BEGIN PRIVATE KEY-----\ndummy\n-----END PRIVATE KEY-----\n",
        google_busy_calendar_ids: [BUSY_CALENDAR_ID],
        google_booking_calendar_id: BOOKING_CALENDAR_ID,
        turnstile_secret_key: nil, # 既定では Turnstile 検証をスキップ
        admin_notification_email: "admin@example.com",
        mail_from: "info@example.com",
        public_base_url: "https://booking-api.example.com",
        cancel_url_base: nil,
        public_rate_limit_per_ip: 120,
        public_rate_limit_period: 60,
        reservation_rate_limit_per_ip: 5,
        reservation_rate_limit_period: 600
      }.merge(overrides)
    )
  end

  def admin_headers(key: ADMIN_API_KEY)
    { "X-Admin-Key" => key }
  end
end
