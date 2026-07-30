# frozen_string_literal: true

# 曜日別の受付時間。start_time / end_time は予約メニューの time_zone における壁時計時刻。
class WeeklyAvailability < ApplicationRecord
  include WallClockTime

  belongs_to :booking_type, inverse_of: :weekly_availabilities

  wall_clock_time :start_time, :end_time

  validates :day_of_week,
            numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 6 }
  validates :start_time, :end_time, presence: true
  validate :end_time_after_start_time

  scope :for_day, ->(day_of_week) { where(day_of_week:) }

  private

  def end_time_after_start_time
    return if start_time.blank? || end_time.blank?
    return if start_minutes < end_minutes

    errors.add(:end_time, "は start_time より後である必要があります")
  end
end
