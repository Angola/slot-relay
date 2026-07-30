# frozen_string_literal: true

# 特定日の受付変更。is_available=false で休業、true かつ時刻ありで時間変更。
class CreateAvailabilityOverrides < ActiveRecord::Migration[8.1]
  def change
    create_table :availability_overrides do |t|
      t.references :booking_type, null: false, foreign_key: true
      t.date       :date, null: false
      t.boolean    :is_available, null: false, default: false
      t.time       :start_time
      t.time       :end_time

      t.timestamps
    end

    add_index :availability_overrides, %i[booking_type_id date], unique: true
    add_check_constraint :availability_overrides,
                         "is_available = false OR (start_time IS NOT NULL AND end_time IS NOT NULL AND start_time < end_time)",
                         name: "availability_overrides_time_order"
  end
end
