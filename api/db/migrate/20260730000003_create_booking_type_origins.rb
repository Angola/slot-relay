# frozen_string_literal: true

# 予約メニューごとの許可 Origin。CORS の許可判定と、公開 API の Origin 検証に使う。
class CreateBookingTypeOrigins < ActiveRecord::Migration[8.1]
  def change
    create_table :booking_type_origins do |t|
      t.references :booking_type, null: false, foreign_key: true
      t.string     :origin, null: false

      t.timestamps
    end

    add_index :booking_type_origins, %i[booking_type_id origin], unique: true
  end
end
