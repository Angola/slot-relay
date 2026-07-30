# frozen_string_literal: true

require "net/http"

# Cloudflare Turnstile のトークン検証。
#
# 公開予約 POST は無認証で開いているため、Bot 対策としてこれを必須にする。
# CORS は防御にならない（HTTP クライアントは Origin を偽装できる）ので、
# Origin 検証・レートリミットと併用する前提。
class TurnstileVerifier
  VERIFY_URL = "https://challenges.cloudflare.com/turnstile/v0/siteverify"
  TIMEOUT_SECONDS = 5

  def initialize(config: SlotRelay.config)
    @config = config
  end

  # シークレット未設定なら検証をスキップする（ローカル開発・テスト向け）。
  # 本番で未設定の場合は起動時に警告を出す（config/initializers/slot_relay.rb）。
  def enabled?
    config.turnstile_configured?
  end

  # @return [Boolean] トークンが有効か
  def verify(token, remote_ip: nil)
    return true unless enabled?
    return false if token.blank?

    response = post_verify(token, remote_ip)
    body = JSON.parse(response.body)
    body["success"] == true
  rescue JSON::ParserError, Net::ReadTimeout, Net::OpenTimeout, SocketError, SystemCallError => e
    # Cloudflare 側の障害で予約を一律に落とさないよう、失敗として扱ったうえでログに残す。
    Rails.logger.error("[slot-relay] Turnstile 検証に失敗しました: #{e.class}: #{e.message}")
    false
  end

  private

  attr_reader :config

  def post_verify(token, remote_ip)
    uri = URI.parse(VERIFY_URL)
    params = { "secret" => config.turnstile_secret_key, "response" => token }
    params["remoteip"] = remote_ip if remote_ip.present?

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = TIMEOUT_SECONDS
    http.read_timeout = TIMEOUT_SECONDS
    http.post(uri.path, URI.encode_www_form(params), "Content-Type" => "application/x-www-form-urlencoded")
  end
end
