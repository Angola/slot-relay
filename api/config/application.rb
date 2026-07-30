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

    # API 専用。セッション・Cookie・flash は使わない。
    config.api_only = true

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
    config.filter_parameters += %i[
      guest name email company phone answers
      turnstileToken turnstile_token
      GOOGLE_SERVICE_ACCOUNT_PRIVATE_KEY private_key
    ]

    # 予約処理は同期で完結させる（ワーカーは MVP 対象外）。メールも同一リクエスト内で送る。
    config.active_job.queue_adapter = :async
  end
end
