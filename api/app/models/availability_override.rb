# frozen_string_literal: true

# 特定日の受付変更。
#   is_available = false            → その日は休業（曜日別設定を無視して枠を作らない）
#   is_available = true  + 時刻あり → その日だけ受付時間を差し替える
class AvailabilityOverride < ApplicationRecord
  include WallClockTime

  belongs_to :booking_type, inverse_of: :availability_overrides

  wall_clock_time :start_time, :end_time

  validates :date, presence: true, uniqueness: { scope: :booking_type_id }
  validate :times_required_when_available
  validate :end_time_after_start_time

  private

  def times_required_when_available
    return unless is_available
    return if start_time.present? && end_time.present?

    errors.add(:start_time, "は is_available=true のとき必須です")
  end

  def end_time_after_start_time
    return if start_time.blank? || end_time.blank?
    return if start_minutes < end_minutes

    errors.add(:end_time, "は start_time より後である必要があります")
  end
end
