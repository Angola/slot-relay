# frozen_string_literal: true

class CreateBookingTypes < ActiveRecord::Migration[8.1]
  def change
    create_table :booking_types do |t|
      t.string  :name, null: false
      t.string  :slug, null: false
      t.text    :description
      t.integer :duration_minutes, null: false, default: 60
      t.string  :time_zone, null: false, default: "Asia/Tokyo"
      t.integer :minimum_notice_minutes, null: false, default: 1440
      t.integer :booking_window_days, null: false, default: 30
      t.integer :buffer_before_minutes, null: false, default: 0
      t.integer :buffer_after_minutes, null: false, default: 0
      # nil のときは ENV の GOOGLE_BOOKING_CALENDAR_ID を使う
      t.string  :google_booking_calendar_id
      t.string  :status, null: false, default: "active"

      t.timestamps
    end

    add_index :booking_types, :slug, unique: true
  end
end
