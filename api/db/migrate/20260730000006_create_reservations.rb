# frozen_string_literal: true

class CreateReservations < ActiveRecord::Migration[8.1]
  def change
    create_table :reservations do |t|
      t.string     :public_id, null: false
      t.references :booking_type, null: false, foreign_key: true
      # 予定を登録する Google カレンダー ID。排他制約のスコープに使うため、
      # BookingType から都度導出せず予約時点の値を非正規化して保持する
      # （あとで予約メニューの登録先カレンダーを変えても、既存予約の直列化範囲が動かないように）。
      t.string     :booking_calendar_id, null: false
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
    add_index :reservations, %i[booking_calendar_id start_at]
    add_index :reservations, :status

    add_check_constraint :reservations, "start_at < end_at", name: "reservations_time_order"

    # 同一の登録先 Google カレンダーについて、有効な予約（pending / confirmed）の
    # 時間帯が重ならないことを DB レベルで保証する。同時リクエストはここで直列化される。
    #
    # スコープを booking_type_id ではなく booking_calendar_id にしているのが要点。
    # 複数の予約メニューは既定で同じ登録先カレンダー（GOOGLE_BOOKING_CALENDAR_ID）を共有するため、
    # メニュー単位でスコープすると「別メニュー・同じカレンダー・同じ時刻」の同時予約が
    # すり抜ける。どちらの pending も互いに衝突せず、Google 予定の作成前なので FreeBusy も
    # 両方«空き»と答えてしまい、同じ時間に 2 件の予定ができる。
    # カレンダー単位でスコープすれば、メニュー単位の直列化も自動的に含まれる。
    #
    # 草案では status = 'pending' のみを対象にしていたが、confirmed も含める。
    # Google カレンダーの FreeBusy には直前に自分が作った予定が即座に反映されない
    # 可能性があり、その窓で二重予約が通ってしまうため。
    #
    # なお前後バッファはこの制約では表現しない（枠の生成・空き判定側で扱う）。
    reversible do |dir|
      dir.up do
        execute <<~SQL.squish
          ALTER TABLE reservations
          ADD CONSTRAINT reservations_active_overlap_exclude
          EXCLUDE USING gist (
            booking_calendar_id WITH =,
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
