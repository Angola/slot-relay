# frozen_string_literal: true

# アプリ全体の設定と、外部依存（Google Calendar / Turnstile）の差し替えポイント。
#
# 環境変数の読み取りはここに集約する。各サービスクラスが直接 ENV を見ると
# テストでの差し替えと本番の設定漏れ検知が難しくなるため。
module SlotRelay
  class ConfigurationError < StandardError; end

  # リポジトリ最上位の VERSION ファイル（GitHub Actions が自動採番する）を参照する。
  # Docker イメージでは VERSION を同梱しないことがあるため APP_VERSION で上書きできる。
  VERSION = ENV["APP_VERSION"].presence ||
            [Rails.root.join("../VERSION"), Rails.root.join("VERSION")]
            .find(&:exist?)&.read&.strip ||
            "unknown"

  Configuration = Struct.new(
    :admin_api_key,
    :google_service_account_email,
    :google_service_account_private_key,
    :google_busy_calendar_ids,
    :google_booking_calendar_id,
    :turnstile_secret_key,
    :admin_notification_email,
    :mail_from,
    :public_base_url,
    :cancel_url_base,
    :public_rate_limit_per_ip,
    :public_rate_limit_period,
    :reservation_rate_limit_per_ip,
    :reservation_rate_limit_period,
    keyword_init: true
  ) do
    def google_configured?
      google_service_account_email.present? && google_service_account_private_key.present?
    end

    def turnstile_configured?
      turnstile_secret_key.present?
    end

    def admin_api_configured?
      admin_api_key.present? && admin_api_key.length >= 32
    end

    # キャンセル画面の URL。予約サイト側に置く場合は CANCEL_URL_BASE で上書きする。
    def cancel_url_for(public_id, token)
      base = (cancel_url_base.presence || public_base_url).to_s.chomp("/")
      "#{base}/c/#{public_id}/#{token}"
    end
  end

  class << self
    def config
      @config ||= build_config
    end

    attr_writer :config

    def build_config
      Configuration.new(
        admin_api_key: ENV["ADMIN_API_KEY"].presence,
        google_service_account_email: ENV["GOOGLE_SERVICE_ACCOUNT_EMAIL"].presence,
        google_service_account_private_key: normalize_private_key(ENV["GOOGLE_SERVICE_ACCOUNT_PRIVATE_KEY"]),
        google_busy_calendar_ids: split_list(ENV["GOOGLE_BUSY_CALENDAR_IDS"]),
        google_booking_calendar_id: ENV["GOOGLE_BOOKING_CALENDAR_ID"].presence,
        turnstile_secret_key: ENV["TURNSTILE_SECRET_KEY"].presence,
        admin_notification_email: ENV["ADMIN_NOTIFICATION_EMAIL"].presence,
        mail_from: ENV["SMTP_FROM"].presence || "info@genba-tsunagu.jp",
        public_base_url: ENV["PUBLIC_BASE_URL"].presence || "https://booking-api.genba-tsunagu.jp",
        cancel_url_base: ENV["CANCEL_URL_BASE"].presence,
        public_rate_limit_per_ip: ENV.fetch("PUBLIC_RATE_LIMIT_PER_IP", "120").to_i,
        public_rate_limit_period: ENV.fetch("PUBLIC_RATE_LIMIT_PERIOD", "60").to_i,
        reservation_rate_limit_per_ip: ENV.fetch("RESERVATION_RATE_LIMIT_PER_IP", "5").to_i,
        reservation_rate_limit_period: ENV.fetch("RESERVATION_RATE_LIMIT_PERIOD", "600").to_i
      )
    end

    # Google Calendar クライアント。テストでは fake を注入する。
    def calendar_client
      @calendar_client ||= default_calendar_client
    end

    attr_writer :calendar_client

    # テスト用。設定・クライアントのメモ化を捨てる。
    def reset!
      @config = nil
      @calendar_client = nil
    end

    private

    def default_calendar_client
      return GoogleCalendar::Client.new if config.google_configured?

      unless Rails.env.local?
        raise ConfigurationError,
              "GOOGLE_SERVICE_ACCOUNT_EMAIL / GOOGLE_SERVICE_ACCOUNT_PRIVATE_KEY が未設定です"
      end

      Rails.logger.warn(
        "[slot-relay] Google サービスアカウント未設定のため NullClient を使用します" \
        "（Busy 時間は空・予定は作成されません）"
      )
      GoogleCalendar::NullClient.new
    end

    # Coolify の環境変数では改行が \n という 2 文字で入ることがあるため復元する。
    def normalize_private_key(raw)
      return nil if raw.blank?

      raw.gsub('\n', "\n")
    end

    def split_list(raw)
      raw.to_s.split(",").map(&:strip).reject(&:blank?)
    end
  end
end
