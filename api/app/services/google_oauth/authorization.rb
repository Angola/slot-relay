# frozen_string_literal: true

module GoogleOauth
  # 同意画面の URL を組み立てる。
  #
  # 管理 API キーを URL に載せないため、フローは 2 段になっている。
  #   1. POST /v1/admin/google/oauth/url （X-Admin-Key）で authUrl を受け取る
  #   2. ブラウザでその URL を開いて同意する
  #
  # state は署名付きトークン（既定 10 分で失効）。DB もキャッシュも使わず、
  # 改ざんは署名で弾く。有効な state を作るには管理 API キーが要る。
  class Authorization
    AUTH_ENDPOINT = "https://accounts.google.com/o/oauth2/v2/auth"
    STATE_PURPOSE = "slot-relay/google-oauth-state"
    STATE_TTL = 10.minutes

    class << self
      # @return [String] 同意画面の URL
      def authorization_url(config: SlotRelay.config)
        params = {
          client_id: config.google_oauth_client_id,
          redirect_uri: config.google_oauth_redirect_uri_or_default,
          response_type: "code",
          scope: GoogleCalendar::Client::SCOPES.join(" "),
          # refresh token を得るために必須。prompt=consent が無いと 2 回目以降は
          # refresh token が返らず、保存するものが無くなる。
          access_type: "offline",
          prompt: "consent",
          include_granted_scopes: "true",
          state: generate_state
        }

        "#{AUTH_ENDPOINT}?#{params.to_query}"
      end

      # 署名対象は nonce の文字列。Hash にするとシリアライザ（既定は JSON）で
      # シンボルキーが文字列に化けるため、素の String にしておく。
      def generate_state
        verifier.generate(SecureRandom.hex(16), purpose: STATE_PURPOSE, expires_in: STATE_TTL)
      end

      # 有効なら true。改ざん・期限切れ・欠落はすべて false。
      def valid_state?(state)
        return false if state.blank?

        verifier.verified(state, purpose: STATE_PURPOSE).present?
      end

      def verifier
        Rails.application.message_verifier(STATE_PURPOSE)
      end
    end
  end
end
