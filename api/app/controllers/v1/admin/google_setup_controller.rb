# frozen_string_literal: true

module V1
  module Admin
    # Google 連携の設定画面（サーバー描画の HTML）。
    #
    #   GET  /v1/admin/google/setup       — 連携状態とカレンダー選択の画面
    #   POST /v1/admin/google/setup       — 選択を保存
    #   POST /v1/admin/google/login       — 管理キーを入力してセッションを得る
    #   POST /v1/admin/google/connect     — Google の同意画面へ送る
    #   POST /v1/admin/google/disconnect  — 連携を解除
    #
    # 認証は次のどちらか。
    #   - 短期セッション Cookie（30 分・SameSite=Strict）。login か OAuth コールバックが発行する
    #   - X-Admin-Key ヘッダ（API クライアントから触るとき）
    #
    # ブラウザは任意のヘッダを付けられないので、直接 URL を開いたときは login フォームを出す。
    # 管理キーは POST のボディで送り、URL・履歴・Referer に残さない。
    #
    # Cookie で認証する唯一の画面なので、POST には CSRF トークンを必須にする。
    class GoogleSetupController < BaseController
      include ActionController::Cookies

      skip_before_action :authenticate_admin!
      before_action :authenticate_setup!, except: :login
      before_action :verify_csrf!, only: %i[update disconnect connect]

      def show
        render_page
      end

      # 管理キーを受け取って設定画面のセッションを発行する。
      # 総当たりは /v1/admin 配下のレートリミット（rack-attack）で抑える。
      def login
        unless admin_key_valid?(params[:adminKey])
          Rails.logger.warn("[slot-relay] 設定画面のログインに失敗しました（IP: #{request.remote_ip}）")
          return render_login(error: "管理 API キーが正しくありません。", status: :unauthorized)
        end

        issue_setup_session!
        redirect_to setup_path, allow_other_host: false
      end

      # 同意画面へ送る。JSON を返す POST /v1/admin/google/oauth/url のブラウザ版。
      def connect
        unless SlotRelay.config.google_oauth_configured?
          return render_page(
            error: "GOOGLE_OAUTH_CLIENT_ID / GOOGLE_OAUTH_CLIENT_SECRET が未設定です。",
            status: :service_unavailable
          )
        end

        redirect_to GoogleOauth::Authorization.authorization_url, allow_other_host: true
      end

      def update
        saved = GoogleCalendarSelection.new(selection_params).call

        if saved.failure?
          render_page(error: saved.message, status: :unprocessable_content)
        else
          render_page(notice: "カレンダーの設定を保存しました。")
        end
      end

      def disconnect
        GoogleConnection.disconnect!
        Rails.logger.info("[slot-relay] Google 連携を解除しました")
        render_page(notice: "Google 連携を解除しました。")
      end

      private

      # 短期セッション Cookie か X-Admin-Key のどちらかがあればよい。
      # どちらも無いブラウザからのアクセスには、ログインフォームを出す。
      def authenticate_setup!
        return if GoogleOauth::SetupSession.valid?(session_cookie)
        return if admin_key_valid?

        render_login(status: :unauthorized)
      end

      # Cookie で認証している場合のみ CSRF トークンを検証する。
      # X-Admin-Key はブラウザが自動送信しないため、そもそも CSRF が成立しない。
      def verify_csrf!
        return if admin_key_valid?
        return if GoogleOauth::SetupSession.valid_csrf?(session_cookie, params[:csrfToken])

        render html: GoogleSetupPage.error_html(
          "フォームの有効期限が切れています。画面を開き直してください。"
        ).html_safe, content_type: "text/html", status: :forbidden # rubocop:disable Rails/OutputSafety
      end

      # @param presented [String, nil] 省略時は X-Admin-Key ヘッダを見る
      def admin_key_valid?(presented = nil)
        return false unless SlotRelay.config.admin_api_configured?

        presented = request.headers["X-Admin-Key"] if presented.nil?
        presented = presented.to_s
        presented.present? &&
          ActiveSupport::SecurityUtils.secure_compare(presented, SlotRelay.config.admin_api_key)
      end

      def issue_setup_session!
        cookies[GoogleOauth::SetupSession::COOKIE_NAME] =
          GoogleOauth::SetupSession.cookie_options.merge(value: GoogleOauth::SetupSession.issue)
      end

      def render_login(error: nil, status: :unauthorized)
        render html: GoogleSetupPage.login_html(error: error).html_safe, # rubocop:disable Rails/OutputSafety
               content_type: "text/html",
               status: status
      end

      def setup_path
        "/v1/admin/google/setup"
      end

      def session_cookie
        cookies[GoogleOauth::SetupSession::COOKIE_NAME]
      end

      def render_page(notice: nil, error: nil, status: :ok)
        html = GoogleSetupPage.new(
          connection: GoogleConnection.current,
          calendars: available_calendars,
          booking_types: BookingType.order(:name).to_a,
          csrf_token: GoogleOauth::SetupSession.csrf_token_for(session_cookie),
          notice: notice,
          error: error || @calendar_error
        ).render

        render html: html.html_safe, content_type: "text/html", status: status # rubocop:disable Rails/OutputSafety
      end

      # 未連携やトークン失効でも画面自体は開けるようにする（そこから再連携するため）。
      def available_calendars
        return [] unless GoogleConnection.connected?

        SlotRelay.calendar_client.calendars
      rescue GoogleCalendar::Client::Error => e
        @calendar_error = "カレンダー一覧を取得できませんでした: #{e.message}"
        []
      end

      # booking_types[<id>][booking_calendar_id] / [busy_calendar_ids][]
      # マスアサインメントは行わず、ID と文字列だけを取り出す。
      def selection_params
        raw = params[:booking_types]
        return {} unless raw.respond_to?(:each_pair)

        raw.to_unsafe_h.each_with_object({}) do |(booking_type_id, attrs), acc|
          next unless attrs.respond_to?(:[])

          acc[booking_type_id.to_i] = {
            booking_calendar_id: string_or_nil(attrs["booking_calendar_id"]),
            busy_calendar_ids: Array(attrs["busy_calendar_ids"]).grep(String).reject(&:blank?)
          }
        end
      end

      def string_or_nil(value)
        value.is_a?(String) && value.present? ? value : nil
      end
    end
  end
end
