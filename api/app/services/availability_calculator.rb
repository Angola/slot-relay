# frozen_string_literal: true

# 予約可能な空き枠を計算する。
#
# 手順（docs/DESIGN.md §3.2）:
#   1. 指定期間を予約メニューのタイムゾーンで日ごとに分割
#   2. 曜日別受付時間から duration_minutes 刻みの枠を生成
#   3. 特定日の休業・時間変更を反映
#   4. 最短受付時間（minimum_notice_minutes）と最大予約可能日（booking_window_days）を反映
#   5. Google FreeBusy API から Busy 時間を取得
#   6. 前後バッファを含めて重複する枠を除外
#   7. 有効な予約（pending / confirmed）と重なる枠を除外
#   8. 開始時刻順に返す
#
# タイムゾーンの取り違えを防ぐため、壁時計時刻と日付の合成はこのクラスの中だけで行う。
class AvailabilityCalculator
  # 1 リクエストで計算できる最大日数。Google FreeBusy 呼び出しと応答サイズを抑えるための上限。
  MAX_RANGE_DAYS = 62

  class RangeTooWide < StandardError; end

  Slot = Data.define(:start_at, :end_at)
  Day = Data.define(:date, :slots)

  # @param booking_type [BookingType]
  # @param from [Date] 取得開始日（予約メニューのタイムゾーンにおける日付）
  # @param to [Date] 取得終了日（含む）
  # @param now [Time] 現在時刻。最短受付時間の基準
  # @param exclude_reservation_id [Integer, nil] 空き判定から除外する予約（自分の仮確保）
  # @param calendar_client [#busy_periods]
  def initialize(booking_type:, from:, to:, now: Time.current, exclude_reservation_id: nil,
                 calendar_client: SlotRelay.calendar_client)
    @booking_type = booking_type
    @from = from
    @to = to
    @now = now
    @exclude_reservation_id = exclude_reservation_id
    @calendar_client = calendar_client
  end

  # @return [Array<Day>] 期間内の各日。枠が 0 件の日も slots: [] で含める
  #   （カレンダー UI が「予約できない日」を描画できるようにするため）
  def call
    raise RangeTooWide, "期間は最大 #{MAX_RANGE_DAYS} 日です" if (to - from).to_i + 1 > MAX_RANGE_DAYS

    return [] if effective_dates.empty?

    Time.use_zone(tz) do
      candidates = effective_dates.to_h { |date| [date, candidate_slots_for(date)] }
      blockers = collect_blockers(candidates.values.flatten)

      candidates.map do |date, slots|
        Day.new(date: date, slots: slots.reject { |slot| blocked?(slot, blockers) })
      end
    end
  end

  # 単一の枠が予約可能かを判定する。予約 POST 直前の再確認に使う。
  def slot_available?(start_at)
    Time.use_zone(tz) do
      date = start_at.in_time_zone(tz).to_date
      day = self.class.new(
        booking_type:, from: date, to: date, now:, exclude_reservation_id:, calendar_client:
      ).call.first

      return false if day.nil?

      day.slots.any? { |slot| slot.start_at == start_at }
    end
  end

  private

  attr_reader :booking_type, :from, :to, :now, :exclude_reservation_id, :calendar_client

  def tz
    booking_type.tz
  end

  # booking_window_days と「過去日は返さない」で期間を切り詰める。
  def effective_dates
    @effective_dates ||= begin
      today = now.in_time_zone(tz).to_date
      window_end = today + booking_type.booking_window_days
      range_start = [from, today].max
      range_end = [to, window_end].min

      range_start > range_end ? [] : (range_start..range_end).to_a
    end
  end

  # 最短受付時間。これより前に始まる枠は返さない。
  def earliest_start_at
    @earliest_start_at ||= now + booking_type.minimum_notice_minutes.minutes
  end

  def candidate_slots_for(date)
    windows_for(date).flat_map { |window| slots_in_window(date, window) }
                     .select { |slot| slot.start_at >= earliest_start_at }
                     .sort_by(&:start_at)
  end

  # その日の受付時間帯（分数の Range 配列）。override があれば曜日別設定を完全に置き換える。
  def windows_for(date)
    override = overrides_by_date[date]

    if override
      return [] unless override.is_available

      return [[override.start_minutes, override.end_minutes]]
    end

    weekly_by_day[date.wday].to_a.map { |wa| [wa.start_minutes, wa.end_minutes] }
  end

  # 枠の開始時刻は「その日の壁時計時刻」として組み立てる。
  # 深夜 0 時に経過分数を足すと、サマータイムのある地域で設定どおりの時刻にならない
  # （春の切り替え日は 1 時間分の欠落が経過時間に含まれ、10:00 設定が 11:00 になる）。
  # 終了時刻は「開始から所要時間ぶんの経過時間」なので、こちらは加算でよい。
  def slots_in_window(date, window)
    start_minutes, end_minutes = window
    duration = booking_type.duration_minutes

    offsets = (start_minutes...end_minutes).step(duration).select { |offset| offset + duration <= end_minutes }
    offsets.map do |offset|
      start_at = tz.local(date.year, date.month, date.day, offset / 60, offset % 60)
      Slot.new(start_at: start_at, end_at: start_at + duration.minutes)
    end
  end

  def overrides_by_date
    @overrides_by_date ||= booking_type.availability_overrides
                                       .where(date: effective_dates.first..effective_dates.last)
                                       .index_by(&:date)
  end

  def weekly_by_day
    @weekly_by_day ||= booking_type.weekly_availabilities.to_a.group_by(&:day_of_week)
  end

  # Google の Busy 時間と DB の有効な予約を、判定用の期間配列にまとめる。
  def collect_blockers(candidate_slots)
    return [] if candidate_slots.empty?

    window_start = candidate_slots.map(&:start_at).min - booking_type.buffer_before_minutes.minutes
    window_end = candidate_slots.map(&:end_at).max + booking_type.buffer_after_minutes.minutes

    google_busy(window_start, window_end) + reservation_busy(window_start, window_end)
  end

  def google_busy(window_start, window_end)
    calendar_ids = busy_calendar_ids
    return [] if calendar_ids.empty?

    calendar_client.busy_periods(calendar_ids:, time_min: window_start, time_max: window_end)
                   .map { |period| [period.start_at, period.end_at] }
  end

  # 空き判定に使うカレンダー。登録先カレンダー自身も必ず含める
  # （Google 側で直接入れた予定や、他メニュー経由の予約を二重に埋めないため）。
  def busy_calendar_ids
    (SlotRelay.config.google_busy_calendar_ids + [booking_type.booking_calendar_id]).compact_blank.uniq
  end

  # DB 上の有効な予約。**予約メニュー単位ではなく登録先カレンダー単位**で引く。
  # 複数の予約メニューは既定で同じカレンダーを共有するため、メニュー単位で見ると
  # 「別メニュー・同じカレンダー」の予約を空きとして返してしまう。
  def reservation_busy(window_start, window_end)
    scope = Reservation.for_calendar(booking_type.booking_calendar_id)
                       .blocking(now)
                       .overlapping(window_start, window_end)
    scope = scope.where.not(id: exclude_reservation_id) if exclude_reservation_id
    scope.pluck(:start_at, :end_at)
  end

  # 枠の前後バッファを含めた占有区間が、いずれかの Busy 区間と重なるか。
  def blocked?(slot, blockers)
    occupied_start = slot.start_at - booking_type.buffer_before_minutes.minutes
    occupied_end = slot.end_at + booking_type.buffer_after_minutes.minutes

    blockers.any? { |busy_start, busy_end| busy_start < occupied_end && busy_end > occupied_start }
  end
end
