# frozen_string_literal: true

require "google/apis/calendar_v3"
require "googleauth"
require "signet/oauth_2/client"

module GoogleOauth
  # 同意画面から戻ってきた認可コードを refresh token に交換し、GoogleConnection に保存する。
  #
  # @return [ServiceResult] 成功時 value は GoogleConnection
  class Callback
    def initialize(code:, state:, config: SlotRelay.config)
      @code = code
      @state = state
      @config = config
    end

    def call
      return failure(:configuration_error, "Google OAuth クライアントが設定されていません。") unless
        config.google_oauth_configured?
      return failure(:bad_request, "認可が確認できませんでした。最初からやり直してください。") unless
        Authorization.valid_state?(state)
      return failure(:bad_request, "認可コードがありません。") if code.blank?

      exchanged = exchange_code
      return exchanged if exchanged.is_a?(ServiceResult)

      client, token_response = exchanged
      refresh_token = client.refresh_token.presence
      if refresh_token.blank?
        # prompt=consent を付けていれば通常は返るが、まれに返らないことがある。
        # そのときは Google アカウントの「サードパーティ製アプリ」から権限を削除して再実行する。
        return failure(
          :bad_request,
          "Google から refresh token が返りませんでした。Google アカウントのセキュリティ設定で " \
          "本アプリの権限を削除してから、もう一度連携してください。"
        )
      end

      email = fetch_account_email(client)
      return email if email.is_a?(ServiceResult)

      connection = GoogleConnection.connect!(
        google_account_email: email,
        refresh_token: refresh_token,
        scopes: granted_scopes(token_response)
      )

      Rails.logger.info("[slot-relay] Google アカウントを連携しました: #{email}")
      ServiceResult.success(connection)
    end

    private

    attr_reader :code, :state, :config

    # @return [Array(Signet::OAuth2::Client, Hash)] トークン取得済みのクライアントと生の応答
    def exchange_code
      client = Signet::OAuth2::Client.new(
        client_id: config.google_oauth_client_id,
        client_secret: config.google_oauth_client_secret,
        token_credential_uri: GoogleCalendar::Client::TOKEN_URI,
        redirect_uri: config.google_oauth_redirect_uri_or_default,
        code: code
      )
      # access_token / refresh_token は client 自身へ反映されるが、
      # 同意されたスコープは client には入らないので生の応答も返す。
      [client, client.fetch_access_token!]
    rescue Signet::AuthorizationError => e
      # redirect_uri の不一致・コードの期限切れ・使い回しはここ。
      # Signet の message は「Server message:」が空になることがあるため、
      # Google が返した本文もそのまま出す（error / error_description が入っている）。
      Rails.logger.error(
        "[slot-relay] 認可コードの交換に失敗しました: #{e.message} / Google の応答: #{google_error_body(e)}"
      )
      failure(:bad_request, "Google との認可に失敗しました。最初からやり直してください。")
    end

    # Signet::AuthorizationError から Google の応答本文を取り出す。
    # 秘密は含まれない（error / error_description のみ）。
    def google_error_body(error)
      response = error.try(:response)
      return "(応答なし)" if response.blank?

      status = response.try(:status)
      body = response.try(:body)
      body = body.read if body.respond_to?(:read)
      "status=#{status} body=#{body.to_s.truncate(500)}"
    rescue StandardError => e
      "(取得できず: #{e.class})"
    end

    # 連携したアカウントを特定する。openid スコープを足さずに済ませるため、
    # primary カレンダーの ID（= アカウントのメールアドレス）を使う。
    def fetch_account_email(client)
      service = Google::Apis::CalendarV3::CalendarService.new
      service.client_options.application_name = "slot-relay"
      service.authorization = client
      service.get_calendar_list("primary").id
    rescue Google::Apis::Error, Signet::AuthorizationError => e
      Rails.logger.error("[slot-relay] 連携アカウントの取得に失敗しました: #{e.class}: #{e.message}")
      failure(:calendar_error, "Google アカウント情報を取得できませんでした。")
    end

    # 実際に同意されたスコープ。Signet は応答の scope を granted_scopes に改名して返す
    # （素の scope で来る実装もありうるので両方見る）。
    def granted_scopes(token_response)
      raw = token_response.is_a?(Hash) ? (token_response["granted_scopes"] || token_response["scope"]) : nil
      Array(raw).flat_map { |scope| scope.to_s.split(" ") }.reject(&:blank?)
    end

    def failure(code, message)
      ServiceResult.failure(code, message)
    end
  end
end
