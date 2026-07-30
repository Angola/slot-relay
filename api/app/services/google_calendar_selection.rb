# frozen_string_literal: true

# 設定画面（と管理 API）から来たカレンダー選択を予約メニューへ保存する。
#
#   { <booking_type_id> => { booking_calendar_id:, busy_calendar_ids: [] } }
#
# 予定の登録先は書き込み権限のあるカレンダーでなければならない。ここでは権限までは
# 確認せず（Google への往復を増やさない）、画面側で候補を writable なものに絞る。
class GoogleCalendarSelection
  def initialize(selections)
    @selections = selections || {}
  end

  # @return [ServiceResult] 成功時 value は更新した BookingType の配列
  def call
    return ServiceResult.success([]) if selections.empty?

    booking_types = BookingType.where(id: selections.keys).index_by(&:id)
    unknown = selections.keys - booking_types.keys
    if unknown.any?
      return ServiceResult.failure(:not_found, "存在しない予約メニューが含まれています: #{unknown.join(", ")}")
    end

    updated = []
    ActiveRecord::Base.transaction do
      selections.each do |booking_type_id, attrs|
        booking_type = booking_types.fetch(booking_type_id)
        booking_type.google_booking_calendar_id = attrs[:booking_calendar_id]
        booking_type.google_busy_calendar_ids = Array(attrs[:busy_calendar_ids]).uniq
        booking_type.save!
        updated << booking_type
      end
    end

    ServiceResult.success(updated)
  rescue ActiveRecord::RecordInvalid => e
    ServiceResult.failure(:validation_failed, e.record.errors.full_messages.join(" / "))
  end

  private

  attr_reader :selections
end
