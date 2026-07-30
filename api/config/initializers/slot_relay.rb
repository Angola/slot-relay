# frozen_string_literal: true

# 起動時の設定チェック。
#
# autoload される定数（SlotRelay）は初期化中に参照できないため to_prepare で行う。
# 本番で必須設定が欠けている状態に気づけるよう、落とさず警告を出す
# （実際の拒否は各エンドポイント側で行う: 管理 API は 503、Google 未設定は起動時例外）。
Rails.application.config.to_prepare do
  next unless Rails.env.production?

  config = SlotRelay.config
  missing = []
  missing << "ADMIN_API_KEY（32 文字以上）" unless config.admin_api_configured?
  missing << "GOOGLE_SERVICE_ACCOUNT_EMAIL / GOOGLE_SERVICE_ACCOUNT_PRIVATE_KEY" unless config.google_configured?
  missing << "GOOGLE_BOOKING_CALENDAR_ID" if config.google_booking_calendar_id.blank?
  missing << "TURNSTILE_SECRET_KEY（未設定だと Bot 対策が無効）" unless config.turnstile_configured?
  missing << "ADMIN_NOTIFICATION_EMAIL（未設定だと管理者通知が飛ばない）" if config.admin_notification_email.blank?

  Rails.logger.warn("[slot-relay] 未設定の環境変数があります: #{missing.join(" / ")}") if missing.any?
end
