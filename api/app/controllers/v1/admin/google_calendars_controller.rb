# frozen_string_literal: true

module V1
  module Admin
    # 連携中の Google アカウントが持つカレンダーの一覧。
    #
    #   GET /v1/admin/google/calendars  （X-Admin-Key）
    #
    # 設定画面の選択肢はこれと同じデータを使う。API 単体でも選べるように公開している。
    class GoogleCalendarsController < BaseController
      def index
        connection = GoogleConnection.current

        render json: {
          connection: GoogleConnectionSerializer.payload(connection),
          calendars: SlotRelay.calendar_client.calendars.map { |entry|
            GoogleConnectionSerializer.calendar_payload(entry)
          }
        }
      rescue GoogleCalendar::Client::Error => e
        render_error(:calendar_error, e.message)
      end
    end
  end
end
