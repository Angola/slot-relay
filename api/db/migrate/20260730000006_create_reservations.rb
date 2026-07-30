# frozen_string_literal: true

class CreateReservations < ActiveRecord::Migration[8.1]
  def change
    create_table :reservations do |t|
      t.string     :public_id, null: false
      t.references :booking_type, null: false, foreign_key: true
      t.string     :google_event_id
      t.datetime   :start_at, null: false
      t.datetime   :end_at, null: false
      t.string     :guest_name, null: false
      t.string     :guest_email, null: false
      t.string     :guest_company
      t.string     :guest_phone
      t.jsonb      :answers, null: false, default: {}
      t.string     :status, null: false, default: "pending"
      t.string     :cancel_token_hash
      t.string     :idempotency_key
      # pending の仮確保 TTL。過ぎた pending は空き枠計算・排他判定から除外し、掃除する。
      t.datetime   :expires_at
      t.datetime   :cancelled_at

      t.timestamps
    end

    add_index :reservations, :public_id, unique: true
    add_index :reservations, :cancel_token_hash, unique: true
    add_index :reservations, %i[booking_type_id idempotency_key],
              unique: true,
              where: "idempotency_key IS NOT NULL",
              name: "index_reservations_on_booking_type_and_idempotency_key"
    add_index :reservations, %i[booking_type_id start_at]
    add_index :reservations, :status

    add_check_constraint :reservations, "start_at < end_at", name: "reservations_time_order"

    # 同一予約メニュー内で、有効な予約（pending / confirmed）の時間帯が重ならないことを
    # DB レベルで保証する。同時リクエストはここで直列化される。
    #
    # 草案では status = 'pending' のみを対象にしていたが、confirmed も含める。
    # Google カレンダーの FreeBusy には直前に自分が作った予定が即座に反映されない
    # 可能性があり、その窓で二重予約が通ってしまうため。
    reversible do |dir|
      dir.up do
        execute <<~SQL.squish
          ALTER TABLE reservations
          ADD CONSTRAINT reservations_active_overlap_exclude
          EXCLUDE USING gist (
            booking_type_id WITH =,
            tstzrange(start_at, end_at, '[)') WITH &&
          )
          WHERE (status IN ('pending', 'confirmed'))
        SQL
      end

      dir.down do
        execute <<~SQL.squish
          ALTER TABLE reservations DROP CONSTRAINT reservations_active_overlap_exclude
        SQL
      end
    end
  end
end
