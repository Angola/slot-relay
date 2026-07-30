# frozen_string_literal: true

# テスト中の SlotRelay.config を固定する。ENV に依存させないことで、
# 実行環境の環境変数でテスト結果が変わるのを防ぐ。
module SlotRelayTestConfig
  ADMIN_API_KEY = "test-admin-key-0123456789abcdef0123456789abcdef"
  BUSY_CALENDAR_ID = "busy@example.com"
  BOOKING_CALENDAR_ID = "booking@example.com"
  OAUTH_CLIENT_ID = "test-client-id.apps.googleusercontent.com"
  OAUTH_CLIENT_SECRET = "test-client-secret"
  GOOGLE_ACCOUNT_EMAIL = "owner@example.com"

  def configure_slot_relay!(**overrides)
    SlotRelay.config = SlotRelay::Configuration.new(
      **{
        admin_api_key: ADMIN_API_KEY,
        google_oauth_client_id: OAUTH_CLIENT_ID,
        google_oauth_client_secret: OAUTH_CLIENT_SECRET,
        google_oauth_redirect_uri: nil,
        google_busy_calendar_ids: [BUSY_CALENDAR_ID],
        google_booking_calendar_id: BOOKING_CALENDAR_ID,
        turnstile_secret_key: nil, # 既定では Turnstile 検証をスキップ
        # 本番の「未設定なら 503」を検証するテストだけ true にする
        require_turnstile: false,
        api_docs_enabled: true,
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

  # Google 連携済みの状態を作る。refresh token は暗号化して保存される。
  def connect_google!(email: GOOGLE_ACCOUNT_EMAIL, refresh_token: "test-refresh-token", scopes: nil)
    GoogleConnection.connect!(
      google_account_email: email,
      refresh_token: refresh_token,
      scopes: scopes || GoogleCalendar::Client::SCOPES
    )
  end
end
