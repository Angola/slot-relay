# frozen_string_literal: true

# Google Calendar クライアントのテスト用差し替え。
# 実 API を叩かずに「Busy 時間がある」「作成に失敗する」状況を作れるようにする。
class FakeCalendarClient
  attr_reader :created_events, :deleted_events, :freebusy_queries
  attr_accessor :busy_periods_by_calendar, :raise_on_busy, :raise_on_create, :raise_on_delete

  def initialize(busy: {})
    @busy_periods_by_calendar = busy
    @created_events = []
    @deleted_events = []
    @freebusy_queries = []
    @raise_on_busy = false
    @raise_on_create = false
    @raise_on_delete = false
  end

  # @param busy [Array<Array(Time, Time)>] Busy 区間
  def add_busy(calendar_id, ranges)
    busy_periods_by_calendar[calendar_id] = (busy_periods_by_calendar[calendar_id] || []) + ranges
  end

  def busy_periods(calendar_ids:, time_min:, time_max:)
    raise GoogleCalendar::Client::Error, "FreeBusy 取得に失敗（テスト）" if raise_on_busy

    freebusy_queries << { calendar_ids: Array(calendar_ids), time_min: time_min, time_max: time_max }

    Array(calendar_ids).flat_map { |id| busy_periods_by_calendar.fetch(id, []) }
                       .select { |start_at, end_at| start_at < time_max && end_at > time_min }
                       .map { |start_at, end_at| GoogleCalendar::Client::BusyPeriod.new(start_at:, end_at:) }
  end

  def create_event(calendar_id:, summary:, description:, start_at:, end_at:, time_zone:, private_properties: {})
    raise GoogleCalendar::Client::Error, "予定の作成に失敗（テスト）" if raise_on_create

    event_id = "fake-event-#{created_events.size + 1}"
    created_events << {
      id: event_id, calendar_id:, summary:, description:, start_at:, end_at:, time_zone:, private_properties:
    }
    event_id
  end

  def delete_event(calendar_id:, event_id:)
    raise GoogleCalendar::Client::Error, "予定の削除に失敗（テスト）" if raise_on_delete

    deleted_events << { calendar_id:, event_id: }
    true
  end
end
