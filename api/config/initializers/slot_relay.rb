# frozen_string_literal: true

# 起動時の設定チェック。
#
# autoload される定数（SlotRelay）は初期化中に参照できないため to_prepare で行う。
# 本番で必須設定が欠けている状態に気づけるよう、落とさず警告を出す
# （実際の拒否は各エンドポイント側で行う: 管理 API は 503、Google 未連携は 502）。
Rails.application.config.to_prepare do
  next unless Rails.env.production?

  config = SlotRelay.config
  missing = []
  missing << "ADMIN_API_KEY（32 文字以上）" unless config.admin_api_configured?
  unless config.google_oauth_configured?
    missing << "GOOGLE_OAUTH_CLIENT_ID / GOOGLE_OAUTH_CLIENT_SECRET"
  end
  missing << "TURNSTILE_SECRET_KEY（未設定だと Bot 対策が無効）" unless config.turnstile_configured?
  missing << "ADMIN_NOTIFICATION_EMAIL（未設定だと管理者通知が飛ばない）" if config.admin_notification_email.blank?

  Rails.logger.warn("[slot-relay] 未設定の環境変数があります: #{missing.join(" / ")}") if missing.any?

  # Google の連携は環境変数ではなく DB に入るので、別途知らせる。
  # マイグレーション前などテーブルが無い状態でも起動を止めない。
  begin
    if config.google_oauth_configured? && !GoogleConnection.connected?
      Rails.logger.warn(
        "[slot-relay] Google アカウントが未連携です。/v1/admin/google/setup から連携するまで " \
        "空き取得と予約登録は 502 になります。"
      )
    end
  rescue ActiveRecord::ActiveRecordError => e
    Rails.logger.warn("[slot-relay] Google 連携状態を確認できませんでした: #{e.class}")
  end
end
