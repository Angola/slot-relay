# frozen_string_literal: true

module GoogleCalendar
  # Google サービスアカウントが未設定のときに使うダミー。
  # ローカル開発・テストでのみ使われ、本番では SlotRelay.calendar_client が例外を投げる。
  class NullClient
    def busy_periods(calendar_ids:, time_min:, time_max:) # rubocop:disable Lint/UnusedMethodArgument
      []
    end

    def create_event(**_options)
      "null-event-#{SecureRandom.hex(8)}"
    end

    def delete_event(**_options)
      true
    end
  end
end
