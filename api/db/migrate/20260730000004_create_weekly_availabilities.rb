# frozen_string_literal: true

# 曜日別の受付時間。時刻は予約メニューの time_zone における壁時計時刻として解釈する。
class CreateWeeklyAvailabilities < ActiveRecord::Migration[8.1]
  def change
    create_table :weekly_availabilities do |t|
      t.references :booking_type, null: false, foreign_key: true
      t.integer    :day_of_week, null: false # 0=日曜 ... 6=土曜
      t.time       :start_time, null: false
      t.time       :end_time, null: false

      t.timestamps
    end

    add_index :weekly_availabilities, %i[booking_type_id day_of_week]
    add_check_constraint :weekly_availabilities,
                         "day_of_week BETWEEN 0 AND 6",
                         name: "weekly_availabilities_day_of_week_range"
    add_check_constraint :weekly_availabilities,
                         "start_time < end_time",
                         name: "weekly_availabilities_time_order"
  end
end
