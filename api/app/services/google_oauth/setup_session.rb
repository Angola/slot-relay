# frozen_string_literal: true

module GoogleOauth
  # Google 連携の設定画面だけで使う短期セッション。
  #
  # 同意直後にブラウザで開く画面なので、X-Admin-Key ヘッダを付けられない。
  # コールバックで署名付きの Cookie を発行し、30 分だけ設定画面を開けるようにする。
  #
  # CSRF 対策は 2 段。
  #   1. Cookie を SameSite=Lax にして、他サイトからの POST に乗らないようにする
  #   2. フォームに署名付きトークンを埋め、Cookie の nonce と一致しなければ拒否する
  #
  # Strict ではなく Lax なのは、Google からのコールバックが「別サイト起点の
  # ナビゲーション」になるため。Strict だとコールバック直後のリダイレクトで
  # Cookie が送られず、連携に成功しても必ずログイン画面に戻ってしまう。
  # Lax でもクロスサイトの POST には送られないので、CSRF 対策は維持される。
  class SetupSession
    COOKIE_NAME = :slot_relay_google_setup
    SESSION_PURPOSE = "slot-relay/google-setup-session"
    CSRF_PURPOSE = "slot-relay/google-setup-csrf"
    TTL = 30.minutes

    class << self
      # 署名対象は nonce の文字列そのものにする。Hash にするとシリアライザ
      # （既定は JSON）でシンボルキーが文字列に化けて取り出せない。
      #
      # @return [String] Cookie に入れる署名付きトークン
      def issue
        verifier.generate(SecureRandom.hex(16), purpose: SESSION_PURPOSE, expires_in: TTL)
      end

      # @return [String, nil] 有効なら nonce、無効・期限切れなら nil
      def nonce_from(token)
        return nil if token.blank?

        verifier.verified(token, purpose: SESSION_PURPOSE).presence
      end

      def valid?(token)
        nonce_from(token).present?
      end

      # セッションに紐づく CSRF トークン。フォームの hidden に入れる。
      # purpose が違うため、セッショントークンをそのまま流用することはできない。
      def csrf_token_for(session_token)
        nonce = nonce_from(session_token)
        return nil if nonce.blank?

        verifier.generate(nonce, purpose: CSRF_PURPOSE, expires_in: TTL)
      end

      # フォームから来た CSRF トークンが、この Cookie のセッションのものか。
      def valid_csrf?(session_token, csrf_token)
        session_nonce = nonce_from(session_token)
        return false if session_nonce.blank? || csrf_token.blank?

        csrf_nonce = verifier.verified(csrf_token, purpose: CSRF_PURPOSE)
        return false if csrf_nonce.blank?

        ActiveSupport::SecurityUtils.secure_compare(csrf_nonce.to_s, session_nonce)
      end

      def cookie_options
        {
          value: nil,
          httponly: true,
          # OAuth コールバック（別サイト起点のリダイレクト）で Cookie が送られるよう Lax にする
          same_site: :lax,
          secure: !Rails.env.local?,
          expires: TTL.from_now,
          path: "/v1/admin/google"
        }
      end

      def verifier
        Rails.application.message_verifier(SESSION_PURPOSE)
      end
    end
  end
end
