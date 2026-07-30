# frozen_string_literal: true

module GoogleCalendar
  # Google が未連携のときに使うダミー。
  # ローカル開発・テストでのみ使われ、本番では UnavailableClient が 502 を返す。
  class NullClient
    # 設定画面の見た目を確認できるよう、それらしいカレンダーを返す。
    LOCAL_CALENDARS = [
      { id: "local-dev@example.com", summary: "メイン（ローカルダミー）", primary: true, access_role: "owner" },
      { id: "local-dev-booking-calendar", summary: "予約用（ローカルダミー）", primary: false, access_role: "owner" },
      { id: "ja.japanese#holiday@group.v.calendar.google.com", summary: "日本の祝日（ローカルダミー）",
        primary: false, access_role: "reader" }
    ].freeze

    def busy_periods(calendar_ids:, time_min:, time_max:) # rubocop:disable Lint/UnusedMethodArgument
      []
    end

    def calendars
      LOCAL_CALENDARS.map { |attrs| Client::CalendarEntry.new(**attrs) }
    end

    def create_event(**_options)
      "null-event-#{SecureRandom.hex(8)}"
    end

    def delete_event(**_options)
      true
    end
  end
end
