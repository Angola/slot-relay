require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "action_controller/railtie"
require "action_mailer/railtie"
require "action_view/railtie"
require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Api
  class Application < Rails::Application
    config.load_defaults 8.1

    config.autoload_lib(ignore: %w[assets tasks])

    # API 専用。公開 API・管理 API は Cookie を一切使わない
    # （公開 API は URL のトークン、管理 API は X-Admin-Key ヘッダで認証する）。
    config.api_only = true

    # 例外は Google 連携の設定画面だけ。同意後にブラウザで開く画面なので、
    # 短期セッションを Cookie で持つ（api_only では Cookie ミドルウェアが外れているため戻す）。
    # 認証に Cookie を使うのは V1::Admin::Google::SetupController のみ。
    config.middleware.insert_before ActionDispatch::RemoteIp, ActionDispatch::Cookies

    # 応答・ログは日本語（CLAUDE.md の方針）。メール本文の日付書式は config/locales/ja.yml。
    config.i18n.default_locale = :ja
    config.i18n.available_locales = %i[ja en]

    # DB は UTC で保存する。予約メニューのタイムゾーンへの変換は
    # AvailabilityCalculator とシリアライザだけが行う（取り違え防止）。
    config.time_zone = "UTC"
    config.active_record.default_timezone = :utc
    # datetime カラムを timestamptz にする設定は config/initializers/timestamptz.rb

    # time カラム（受付時間の start_time / end_time）はタイムゾーン変換の対象にしない。
    # あれは「予約メニューのタイムゾーンにおける壁時計時刻」なので、読み出し時の
    # Time.zone に応じて 10:00 → 19:00 とずれてはならない。
    config.active_record.time_zone_aware_types = [:datetime]

    # 予約者の個人情報をログに残さない（docs/SECURITY.md）。
    # Google OAuth の認可コード・トークン・state もログに残さない。
    config.filter_parameters += %i[
      guest name email company phone answers
      turnstileToken turnstile_token
      code state refresh_token access_token client_secret
      GOOGLE_OAUTH_CLIENT_SECRET
    ]

    # 予約処理は同期で完結させる（ワーカーは MVP 対象外）。メールも同一リクエスト内で送る。
    config.active_job.queue_adapter = :async
  end
end
