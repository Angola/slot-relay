# frozen_string_literal: true

require "google/apis/calendar_v3"
require "googleauth"

module GoogleCalendar
  # Google Calendar API（サービスアカウント）のラッパ。
  #
  # 空き判定は FreeBusy API だけを使う。予定の件名・説明・参加者は一切取得しないため、
  # 個人カレンダーは「予定の時間枠のみ表示」権限で共有すれば足りる。
  class Client
    class Error < StandardError; end

    SCOPES = ["https://www.googleapis.com/auth/calendar"].freeze

    BusyPeriod = Data.define(:start_at, :end_at)

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

    # 予約確定時の予定作成。作成した Google イベント ID を返す。
    #
    # 参加者（attendees）は追加しない。ドメイン全体の委任がないサービスアカウントでは
    # 招待を送れず、確認メールは自前の SMTP で送るため必要がない。
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

    def authorizer
      Google::Auth::ServiceAccountCredentials.make_creds(
        json_key_io: StringIO.new(service_account_json),
        scope: SCOPES
      )
    end

    def service_account_json
      {
        type: "service_account",
        client_email: config.google_service_account_email,
        private_key: config.google_service_account_private_key,
        token_uri: "https://oauth2.googleapis.com/token"
      }.to_json
    end

    def with_error_handling
      yield
    rescue Google::Apis::Error => e
      # 秘密鍵やゲストの個人情報がログに乗らないよう、Google 由来のメッセージだけを残す。
      raise Error, "Google Calendar API エラー: #{e.class}: #{e.message}"
    end
  end
end
