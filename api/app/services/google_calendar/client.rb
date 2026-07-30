# frozen_string_literal: true

require "google/apis/calendar_v3"
require "googleauth"

module GoogleCalendar
  # Google Calendar API（ユーザー OAuth）のラッパ。
  #
  # 認証は GoogleConnection に保存した refresh token を使う。アクセストークンは
  # googleauth（Signet）が期限切れ時に自動で取り直すため、ここでは管理しない。
  #
  # 空き判定は FreeBusy API だけを使い、予定の件名・説明・参加者は取得しない。
  class Client
    class Error < StandardError; end

    # 全権の calendar スコープではなく、必要な操作ごとに最小のものを要求する。
    SCOPES = [
      # 設定画面に出すカレンダー一覧
      "https://www.googleapis.com/auth/calendar.calendarlist.readonly",
      # 空き判定（FreeBusy のみ。予定の内容は読まない）
      "https://www.googleapis.com/auth/calendar.freebusy",
      # 予約の予定を作成・削除する
      "https://www.googleapis.com/auth/calendar.events"
    ].freeze

    TOKEN_URI = "https://oauth2.googleapis.com/token"

    BusyPeriod = Data.define(:start_at, :end_at)

    # 設定画面に出すカレンダー 1 件。
    CalendarEntry = Data.define(:id, :summary, :primary, :access_role) do
      # 予定を作れるカレンダーか（登録先の候補になるのはこれだけ）。
      def writable?
        %w[owner writer].include?(access_role)
      end
    end

    def initialize(config: SlotRelay.config)
      @config = config
    end

    # 指定カレンダー群の Busy 時間を取得する。
    # 個々のカレンダーで権限エラー等が起きた場合は「判定できない」ため例外にする
    # （黙って空配列を返すと空いていない枠を空きとして返してしまう）。
    def busy_periods(calendar_ids:, time_min:, time_max:)
      ids = Array(calendar_ids).reject(&:blank?)
      return [] if ids.empty?

      request = Google::Apis::CalendarV3::FreeBusyRequest.new(
        time_min: time_min.utc.iso8601,
        time_max: time_max.utc.iso8601,
        items: ids.map { |id| Google::Apis::CalendarV3::FreeBusyRequestItem.new(id: id) }
      )

      response = with_error_handling { service.query_freebusy(request) }

      (response.calendars || {}).flat_map do |calendar_id, calendar|
        if calendar.errors.present?
          reasons = calendar.errors.map(&:reason).join(", ")
          raise Error, "カレンダー #{calendar_id} の FreeBusy 取得に失敗しました: #{reasons}"
        end

        (calendar.busy || []).map do |period|
          BusyPeriod.new(start_at: Time.zone.parse(period.start.to_s), end_at: Time.zone.parse(period.end.to_s))
        end
      end
    end

    # 連携アカウントが持つカレンダーの一覧。設定画面の選択肢に使う。
    # 権限が無いものも含めて返し、書き込み可否は CalendarEntry#writable? で判定する。
    def calendars
      entries = []
      page_token = nil

      loop do
        response = with_error_handling { service.list_calendar_lists(page_token: page_token, max_results: 250) }
        entries.concat(
          (response.items || []).map do |item|
            CalendarEntry.new(
              id: item.id,
              summary: item.summary_override.presence || item.summary,
              primary: item.primary == true,
              access_role: item.access_role
            )
          end
        )
        page_token = response.next_page_token
        break if page_token.blank?
      end

      # primary を先頭に、あとは表示名順。
      entries.sort_by { |entry| [entry.primary ? 0 : 1, entry.summary.to_s] }
    end

    # 予約確定時の予定作成。作成した Google イベント ID を返す。
    #
    # 参加者（attendees）は追加しない。確認メールは自前の SMTP で送っているため。
    # OAuth 化で招待自体は送れるようになったが、挙動の変更は別途判断する
    # （docs/plans/2026-07-30-google-oauth-calendar-selection.md の積み残し）。
    def create_event(calendar_id:, summary:, description:, start_at:, end_at:, time_zone:, private_properties: {})
      event = Google::Apis::CalendarV3::Event.new(
        summary: summary,
        description: description,
        start: Google::Apis::CalendarV3::EventDateTime.new(date_time: start_at.iso8601, time_zone: time_zone),
        end: Google::Apis::CalendarV3::EventDateTime.new(date_time: end_at.iso8601, time_zone: time_zone),
        extended_properties: Google::Apis::CalendarV3::Event::ExtendedProperties.new(
          private: private_properties.transform_keys(&:to_s)
        )
      )

      created = with_error_handling { service.insert_event(calendar_id, event) }
      created.id
    end

    # 予定削除。すでに存在しない場合は成功として扱う（キャンセルの冪等性）。
    def delete_event(calendar_id:, event_id:)
      with_error_handling { service.delete_event(calendar_id, event_id) }
      true
    rescue Error => e
      raise unless e.message.include?("404") || e.message.include?("410")

      true
    end

    private

    attr_reader :config

    def service
      @service ||= Google::Apis::CalendarV3::CalendarService.new.tap do |svc|
        svc.client_options.application_name = "slot-relay"
        svc.request_options.retries = 2
        svc.authorization = authorizer
      end
    end

    # 保存済みの refresh token からアクセストークンを取り直す資格情報。
    # Signet が期限切れを検知して自動で更新するため、こちらでの管理は不要。
    def authorizer
      connection = GoogleConnection.current
      refresh_token = connection&.refresh_token

      if refresh_token.blank?
        raise Error, "Google アカウントが未連携です。/v1/admin/google/setup から連携してください。"
      end

      Google::Auth::UserRefreshCredentials.new(
        client_id: config.google_oauth_client_id,
        client_secret: config.google_oauth_client_secret,
        refresh_token: refresh_token,
        scope: SCOPES
      )
    end

    def with_error_handling
      yield
    rescue Signet::AuthorizationError => e
      # refresh token が失効・取り消された（invalid_grant）ときはここに来る。
      # 同意画面が「テスト中」だと 7 日で失効するため、再連携を促すメッセージにする。
      raise Error,
            "Google の認可が失効しています（再連携が必要です）: #{e.message}"
    rescue Google::Apis::Error => e
      # client_secret やゲストの個人情報がログに乗らないよう、Google 由来のメッセージだけを残す。
      raise Error, "Google Calendar API エラー: #{e.class}: #{e.message}"
    end
  end
end
