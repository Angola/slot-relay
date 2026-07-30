# frozen_string_literal: true

# 公開 API のレートリミット。
#
# 公開予約 POST は無認証で開いているため、Turnstile と併せて必ず入れる。
# 設定値は SlotRelay.config ではなく ENV から直接読む（初期化中に autoload される定数を
# 参照しないため。Rails では初期化時の autoload が禁止されている）。
class Rack::Attack
  # カウンタは各プロセスのメモリに持つ。単一コンテナ・単一プロセス運用を前提とした割り切りで、
  # Puma を複数ワーカーで動かすとワーカー数ぶん緩くなる（docs/SECURITY.md に記載）。
  self.cache.store = ActiveSupport::Cache::MemoryStore.new(size: 8.megabytes)

  PUBLIC_LIMIT = ENV.fetch("PUBLIC_RATE_LIMIT_PER_IP", "120").to_i
  PUBLIC_PERIOD = ENV.fetch("PUBLIC_RATE_LIMIT_PERIOD", "60").to_i
  RESERVATION_LIMIT = ENV.fetch("RESERVATION_RATE_LIMIT_PER_IP", "5").to_i
  RESERVATION_PERIOD = ENV.fetch("RESERVATION_RATE_LIMIT_PERIOD", "600").to_i
  ADMIN_LIMIT = ENV.fetch("ADMIN_RATE_LIMIT_PER_IP", "60").to_i
  ADMIN_PERIOD = ENV.fetch("ADMIN_RATE_LIMIT_PERIOD", "60").to_i

  RESERVATION_PATH = %r{\A/v1/public/booking-types/[^/]+/reservations\z}
  CANCEL_PATH = %r{\A/v1/public/reservations/[^/]+/cancel\z}

  # 公開 API 全体（空き枠の総なめを抑える）
  throttle("public/ip", limit: PUBLIC_LIMIT, period: PUBLIC_PERIOD) do |request|
    request.ip if request.path.start_with?("/v1/public") && request.request_method != "OPTIONS"
  end

  # 予約の作成・キャンセル（書き込み）はさらに厳しく
  throttle("reservations/ip", limit: RESERVATION_LIMIT, period: RESERVATION_PERIOD) do |request|
    if request.post? && (RESERVATION_PATH.match?(request.path) || CANCEL_PATH.match?(request.path))
      request.ip
    end
  end

  # 管理 API のキー総当たり対策
  throttle("admin/ip", limit: ADMIN_LIMIT, period: ADMIN_PERIOD) do |request|
    request.ip if request.path.start_with?("/v1/admin")
  end

  # 429 のレスポンス形式は他のエラーと揃える（ApplicationController#render_error 相当）
  self.throttled_responder = lambda do |request|
    match_data = request.env["rack.attack.match_data"] || {}
    retry_after = (match_data[:period] || 60).to_i

    [
      429,
      { "Content-Type" => "application/json", "Retry-After" => retry_after.to_s },
      [{ code: "RATE_LIMITED", message: "リクエストが多すぎます。しばらく待って再度お試しください。" }.to_json]
    ]
  end
end
