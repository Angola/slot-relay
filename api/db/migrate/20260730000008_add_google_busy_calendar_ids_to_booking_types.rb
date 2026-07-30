# frozen_string_literal: true

# 空き判定に使うカレンダーを予約メニュー単位で選べるようにする。
# 従来は環境変数 GOOGLE_BUSY_CALENDAR_IDS の全体設定しかなかった。
# 空配列のときは従来どおり環境変数を既定値として使う（移行期の互換）。
class AddGoogleBusyCalendarIdsToBookingTypes < ActiveRecord::Migration[8.1]
  def change
    add_column :booking_types, :google_busy_calendar_ids, :string, array: true, null: false, default: []
  end
end
