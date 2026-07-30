# frozen_string_literal: true

require "test_helper"

module V1
  module Admin
    # 設定画面。認証（Cookie / X-Admin-Key）と CSRF、そして保存が主な検証対象。
    class GoogleSetupControllerTest < ActionDispatch::IntegrationTest
      SETUP_PATH = "/v1/admin/google/setup"
      DISCONNECT_PATH = "/v1/admin/google/disconnect"

      setup do
        @booking_type = create_booking_type
      end

      # --- 認証 ---

      LOGIN_PATH = "/v1/admin/google/login"
      CONNECT_PATH = "/v1/admin/google/connect"

      test "認証が無ければ 401 でログインフォームを返す" do
        get SETUP_PATH

        assert_response :unauthorized
        assert_equal "text/html", response.media_type
        # ブラウザはヘッダを付けられないので、その場でログインできる導線を出す
        assert_includes response.body, %(action="#{LOGIN_PATH}")
        assert_includes response.body, %(name="adminKey")
      end

      # --- ログイン（ブラウザからの導線） ---

      test "管理キーを POST するとセッションが発行され設定画面へ進む" do
        post LOGIN_PATH, params: { adminKey: SlotRelayTestConfig::ADMIN_API_KEY }

        assert_redirected_to SETUP_PATH
        assert GoogleOauth::SetupSession.valid?(cookies[GoogleOauth::SetupSession::COOKIE_NAME.to_s])

        follow_redirect!
        assert_response :ok
      end

      test "間違った管理キーではセッションを発行しない" do
        post LOGIN_PATH, params: { adminKey: "wrong-key" }

        assert_response :unauthorized
        assert_includes response.body, "正しくありません"
        assert_not GoogleOauth::SetupSession.valid?(cookies[GoogleOauth::SetupSession::COOKIE_NAME.to_s].to_s)
      end

      test "管理キーが空でも通らない" do
        post LOGIN_PATH, params: { adminKey: "" }

        assert_response :unauthorized
      end

      test "管理キーが未設定なら誰も入れない" do
        configure_slot_relay!(admin_api_key: nil)

        post LOGIN_PATH, params: { adminKey: "" }

        assert_response :unauthorized
      end

      # --- 連携の開始（ブラウザからの導線） ---

      test "連携ボタンから Google の同意画面へリダイレクトする" do
        token = set_setup_cookie

        post CONNECT_PATH, params: { csrfToken: GoogleOauth::SetupSession.csrf_token_for(token) }

        assert_response :redirect
        assert response.location.start_with?(GoogleOauth::Authorization::AUTH_ENDPOINT)
      end

      test "連携ボタンも CSRF トークンを要求する" do
        set_setup_cookie

        post CONNECT_PATH

        assert_response :forbidden
      end

      test "OAuth クライアント未設定なら連携ボタンは 503" do
        configure_slot_relay!(google_oauth_client_id: nil, google_oauth_client_secret: nil)

        post CONNECT_PATH, headers: admin_headers

        assert_response :service_unavailable
        assert_includes response.body, "GOOGLE_OAUTH_CLIENT_ID"
      end

      test "X-Admin-Key で開ける" do
        connect_google!

        get SETUP_PATH, headers: admin_headers

        assert_response :ok
        assert_includes response.body, SlotRelayTestConfig::GOOGLE_ACCOUNT_EMAIL
      end

      test "短期セッション Cookie で開ける" do
        connect_google!
        set_setup_cookie

        get SETUP_PATH

        assert_response :ok
      end

      test "期限切れのセッション Cookie では開けない" do
        connect_google!
        set_setup_cookie

        travel(GoogleOauth::SetupSession::TTL + 1.minute) do
          get SETUP_PATH

          assert_response :unauthorized
        end
      end

      test "偽造した Cookie では開けない" do
        connect_google!
        cookies[GoogleOauth::SetupSession::COOKIE_NAME] = "forged-token"

        get SETUP_PATH

        assert_response :unauthorized
      end

      # --- 表示 ---

      test "未連携でも画面は開き、連携を促す" do
        get SETUP_PATH, headers: admin_headers

        assert_response :ok
        assert_includes response.body, "Google 未連携"
      end

      test "連携済みならカレンダーの選択肢が出る" do
        connect_google!

        get SETUP_PATH, headers: admin_headers

        assert_response :ok
        # 書き込み権限のあるものは登録先の候補になる
        assert_includes response.body, "booking@example.com"
        # reader は空き判定にだけ使える
        assert_includes response.body, "holiday@example.com"
        assert_includes response.body, @booking_type.name
      end

      test "登録先カレンダーの候補は書き込み権限のあるものだけ" do
        connect_google!

        get SETUP_PATH, headers: admin_headers

        radios = response.body.scan(
          /<input type="radio" name="booking_types\[#{@booking_type.id}\]\[booking_calendar_id\]" value="([^"]*)"/
        ).flatten

        assert_includes radios, "booking@example.com"
        assert_not_includes radios, "holiday@example.com"
      end

      test "同意されていないスコープがあれば警告する" do
        connect_google!(scopes: GoogleCalendar::Client::SCOPES.first(1))

        get SETUP_PATH, headers: admin_headers

        assert_includes response.body, "同意されていない権限があります"
      end

      test "カレンダー取得に失敗しても画面は開き、理由を出す" do
        connect_google!
        fake_calendar.raise_on_calendars = true

        get SETUP_PATH, headers: admin_headers

        assert_response :ok
        assert_includes response.body, "カレンダー一覧を取得できませんでした"
      end

      test "画面に refresh token は出さない" do
        connect_google!(refresh_token: "1//super-secret")

        get SETUP_PATH, headers: admin_headers

        assert_not_includes response.body, "1//super-secret"
      end

      # --- 保存 ---

      test "選択したカレンダーを保存する" do
        connect_google!

        post SETUP_PATH, headers: admin_headers, params: {
          booking_types: {
            @booking_type.id.to_s => {
              booking_calendar_id: "booking@example.com",
              busy_calendar_ids: ["", "owner@example.com", "holiday@example.com"]
            }
          }
        }

        assert_response :ok
        assert_includes response.body, "保存しました"

        @booking_type.reload
        assert_equal "booking@example.com", @booking_type.google_booking_calendar_id
        assert_equal %w[owner@example.com holiday@example.com], @booking_type.google_busy_calendar_ids
      end

      test "空き判定のカレンダーを全部外せる" do
        connect_google!
        @booking_type.update!(google_busy_calendar_ids: ["owner@example.com"])

        post SETUP_PATH, headers: admin_headers, params: {
          booking_types: {
            @booking_type.id.to_s => { booking_calendar_id: "booking@example.com", busy_calendar_ids: [""] }
          }
        }

        assert_response :ok
        assert_empty @booking_type.reload.google_busy_calendar_ids
      end

      test "登録先を「指定しない」にすると環境変数の既定値へ戻る" do
        connect_google!
        @booking_type.update!(google_booking_calendar_id: "booking@example.com")

        post SETUP_PATH, headers: admin_headers, params: {
          booking_types: {
            @booking_type.id.to_s => { booking_calendar_id: "", busy_calendar_ids: [""] }
          }
        }

        assert_response :ok
        @booking_type.reload
        assert_nil @booking_type.google_booking_calendar_id
        assert_equal SlotRelayTestConfig::BOOKING_CALENDAR_ID, @booking_type.booking_calendar_id
      end

      test "存在しない予約メニューを指定したらエラーになる" do
        connect_google!

        post SETUP_PATH, headers: admin_headers, params: {
          booking_types: { "999999" => { booking_calendar_id: "booking@example.com" } }
        }

        assert_response :unprocessable_content
        assert_includes response.body, "存在しない予約メニュー"
      end

      # --- CSRF ---

      # factory が booking@example.com を入れているので、別の値へ変えようとして
      # 「変わっていないこと」を確かめる。
      NEW_CALENDAR = "owner@example.com"

      test "Cookie 認証の POST は CSRF トークンが無いと 403" do
        connect_google!
        set_setup_cookie

        post SETUP_PATH, params: {
          booking_types: { @booking_type.id.to_s => { booking_calendar_id: NEW_CALENDAR } }
        }

        assert_response :forbidden
        assert_equal SlotRelayTestConfig::BOOKING_CALENDAR_ID, @booking_type.reload.google_booking_calendar_id
      end

      test "Cookie 認証の POST は正しい CSRF トークンがあれば通る" do
        connect_google!
        token = set_setup_cookie

        post SETUP_PATH, params: {
          csrfToken: GoogleOauth::SetupSession.csrf_token_for(token),
          booking_types: { @booking_type.id.to_s => { booking_calendar_id: NEW_CALENDAR } }
        }

        assert_response :ok
        assert_equal NEW_CALENDAR, @booking_type.reload.google_booking_calendar_id
      end

      test "別セッションの CSRF トークンでは通らない" do
        connect_google!
        set_setup_cookie
        other = GoogleOauth::SetupSession.issue

        post SETUP_PATH, params: {
          csrfToken: GoogleOauth::SetupSession.csrf_token_for(other),
          booking_types: { @booking_type.id.to_s => { booking_calendar_id: NEW_CALENDAR } }
        }

        assert_response :forbidden
        assert_equal SlotRelayTestConfig::BOOKING_CALENDAR_ID, @booking_type.reload.google_booking_calendar_id
      end

      test "X-Admin-Key の POST は CSRF トークン不要（ブラウザが自動送信しないため）" do
        connect_google!

        post SETUP_PATH, headers: admin_headers, params: {
          booking_types: { @booking_type.id.to_s => { booking_calendar_id: NEW_CALENDAR } }
        }

        assert_response :ok
        assert_equal NEW_CALENDAR, @booking_type.reload.google_booking_calendar_id
      end

      # --- 連携解除 ---

      test "連携を解除できる" do
        connect_google!

        post DISCONNECT_PATH, headers: admin_headers

        assert_response :ok
        assert_not GoogleConnection.connected?
        assert_includes response.body, "解除しました"
      end

      test "解除も CSRF トークンを要求する" do
        connect_google!
        set_setup_cookie

        post DISCONNECT_PATH

        assert_response :forbidden
        assert GoogleConnection.connected?
      end

      private

      # @return [String] 発行したセッショントークン
      def set_setup_cookie
        token = GoogleOauth::SetupSession.issue
        cookies[GoogleOauth::SetupSession::COOKIE_NAME] = token
        token
      end
    end
  end
end
