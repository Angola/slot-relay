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
    :google_oauth_client_id,
    :google_oauth_client_secret,
    :google_oauth_redirect_uri,
    :google_busy_calendar_ids,
    :google_booking_calendar_id,
    :turnstile_secret_key,
    # Turnstile を必須にするか。true なら未設定のとき予約 POST を 503 にする
    # （「未設定なら素通し」を本番で起こさないため）
    :require_turnstile,
    # API ドキュメント（/docs・/openapi.json）を公開するか
    :api_docs_enabled,
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
    # OAuth クライアント（Google Cloud の「ウェブ アプリケーション」）が設定されているか。
    # 実際に API を呼べるかは、これに加えて GoogleConnection の連携が要る。
    def google_oauth_configured?
      google_oauth_client_id.present? && google_oauth_client_secret.present?
    end

    # 同意後に Google が戻ってくる URL。Google Cloud 側の「承認済みのリダイレクト URI」と
    # 完全一致していないと redirect_uri_mismatch になる。
    def google_oauth_redirect_uri_or_default
      google_oauth_redirect_uri.presence ||
        "#{public_base_url.to_s.chomp("/")}/v1/admin/google/oauth/callback"
    end

    def turnstile_configured?
      turnstile_secret_key.present?
    end

    # 「必須なのに未設定」= 予約を受けてはいけない状態。
    # 管理 API キーが未設定なら 503 にするのと同じ考え方（docs/SECURITY.md）。
    def turnstile_missing?
      require_turnstile && !turnstile_configured?
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
        google_oauth_client_id: ENV["GOOGLE_OAUTH_CLIENT_ID"].presence,
        google_oauth_client_secret: ENV["GOOGLE_OAUTH_CLIENT_SECRET"].presence,
        google_oauth_redirect_uri: ENV["GOOGLE_OAUTH_REDIRECT_URI"].presence,
        google_busy_calendar_ids: split_list(ENV["GOOGLE_BUSY_CALENDAR_IDS"]),
        google_booking_calendar_id: ENV["GOOGLE_BOOKING_CALENDAR_ID"].presence,
        turnstile_secret_key: ENV["TURNSTILE_SECRET_KEY"].presence,
        # 本番は Turnstile を必須にする。ローカル・テストは未設定でも通す
        require_turnstile: Rails.env.production?,
        # ドキュメントは本番では既定で閉じる（管理 API の構成を見せないため）。
        # 本番でも読みたいときは ENABLE_API_DOCS=true を設定する。
        api_docs_enabled: Rails.env.local? || ENV["ENABLE_API_DOCS"] == "true",
        admin_notification_email: ENV["ADMIN_NOTIFICATION_EMAIL"].presence,
        mail_from: ENV["SMTP_FROM"].presence || "info@genba-tsunagu.jp",
        public_base_url: ENV["PUBLIC_BASE_URL"].presence || "https://booking-api.stagehubs.net",
        cancel_url_base: ENV["CANCEL_URL_BASE"].presence,
        public_rate_limit_per_ip: ENV.fetch("PUBLIC_RATE_LIMIT_PER_IP", "120").to_i,
        public_rate_limit_period: ENV.fetch("PUBLIC_RATE_LIMIT_PERIOD", "60").to_i,
        reservation_rate_limit_per_ip: ENV.fetch("RESERVATION_RATE_LIMIT_PER_IP", "5").to_i,
        reservation_rate_limit_period: ENV.fetch("RESERVATION_RATE_LIMIT_PERIOD", "600").to_i
      )
    end

    # Google Calendar クライアント。テストでは fake を注入する。
    #
    # 既定のクライアントはメモ化しない。OAuth の連携／解除は実行中に切り替わるため、
    # 起動時の状態を握り続けると連携直後に反映されない。
    def calendar_client
      @calendar_client || default_calendar_client
    end

    attr_writer :calendar_client

    # テスト用。設定・クライアントのメモ化を捨てる。
    def reset!
      @config = nil
      @calendar_client = nil
    end

    private

    def default_calendar_client
      return GoogleCalendar::Client.new if google_ready?

      # 本番で NullClient に落とすと「Busy 時間が空」＝全部空きとして予約を受けてしまう。
      # 使おうとした時点で 502 になるクライアントを返し、静かな取りこぼしを防ぐ。
      return GoogleCalendar::UnavailableClient.new(unavailable_reason) unless Rails.env.local?

      Rails.logger.warn(
        "[slot-relay] Google 未連携のため NullClient を使用します" \
        "（#{unavailable_reason} / Busy 時間は空・予定は作成されません）"
      )
      GoogleCalendar::NullClient.new
    end

    def google_ready?
      config.google_oauth_configured? && GoogleConnection.connected?
    end

    def unavailable_reason
      if config.google_oauth_configured?
        "Google アカウントが未連携です。/v1/admin/google/setup から連携してください"
      else
        "GOOGLE_OAUTH_CLIENT_ID / GOOGLE_OAUTH_CLIENT_SECRET が未設定です"
      end
    end

    def split_list(raw)
      raw.to_s.split(",").map(&:strip).reject(&:blank?)
    end
  end
end
