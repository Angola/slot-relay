# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_07_30_000006) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "btree_gist"
  enable_extension "pg_catalog.plpgsql"

  create_table "availability_overrides", force: :cascade do |t|
    t.bigint "booking_type_id", null: false
    t.datetime "created_at", null: false
    t.date "date", null: false
    t.time "end_time"
    t.boolean "is_available", default: false, null: false
    t.time "start_time"
    t.datetime "updated_at", null: false
    t.index ["booking_type_id", "date"], name: "index_availability_overrides_on_booking_type_id_and_date", unique: true
    t.index ["booking_type_id"], name: "index_availability_overrides_on_booking_type_id"
    t.check_constraint "is_available = false OR start_time IS NOT NULL AND end_time IS NOT NULL AND start_time < end_time", name: "availability_overrides_time_order"
  end

  create_table "booking_type_origins", force: :cascade do |t|
    t.bigint "booking_type_id", null: false
    t.datetime "created_at", null: false
    t.string "origin", null: false
    t.datetime "updated_at", null: false
    t.index ["booking_type_id", "origin"], name: "index_booking_type_origins_on_booking_type_id_and_origin", unique: true
    t.index ["booking_type_id"], name: "index_booking_type_origins_on_booking_type_id"
  end

  create_table "booking_types", force: :cascade do |t|
    t.integer "booking_window_days", default: 30, null: false
    t.integer "buffer_after_minutes", default: 0, null: false
    t.integer "buffer_before_minutes", default: 0, null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.integer "duration_minutes", default: 60, null: false
    t.string "google_booking_calendar_id"
    t.integer "minimum_notice_minutes", default: 1440, null: false
    t.string "name", null: false
    t.string "slug", null: false
    t.string "status", default: "active", null: false
    t.string "time_zone", default: "Asia/Tokyo", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_booking_types_on_slug", unique: true
  end

  create_table "reservations", force: :cascade do |t|
    t.jsonb "answers", default: {}, null: false
    t.bigint "booking_type_id", null: false
    t.string "cancel_token_hash"
    t.datetime "cancelled_at"
    t.datetime "created_at", null: false
    t.datetime "end_at", null: false
    t.datetime "expires_at"
    t.string "google_event_id"
    t.string "guest_company"
    t.string "guest_email", null: false
    t.string "guest_name", null: false
    t.string "guest_phone"
    t.string "idempotency_key"
    t.string "public_id", null: false
    t.datetime "start_at", null: false
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["booking_type_id", "idempotency_key"], name: "index_reservations_on_booking_type_and_idempotency_key", unique: true, where: "(idempotency_key IS NOT NULL)"
    t.index ["booking_type_id", "start_at"], name: "index_reservations_on_booking_type_id_and_start_at"
    t.index ["booking_type_id"], name: "index_reservations_on_booking_type_id"
    t.index ["cancel_token_hash"], name: "index_reservations_on_cancel_token_hash", unique: true
    t.index ["public_id"], name: "index_reservations_on_public_id", unique: true
    t.index ["status"], name: "index_reservations_on_status"
    t.check_constraint "start_at < end_at", name: "reservations_time_order"
    t.exclusion_constraint "booking_type_id WITH =, tstzrange(start_at, end_at, '[)'::text) WITH &&", where: "(status)::text = ANY ((ARRAY['pending'::character varying, 'confirmed'::character varying])::text[])", using: :gist, name: "reservations_active_overlap_exclude"
  end

  create_table "weekly_availabilities", force: :cascade do |t|
    t.bigint "booking_type_id", null: false
    t.datetime "created_at", null: false
    t.integer "day_of_week", null: false
    t.time "end_time", null: false
    t.time "start_time", null: false
    t.datetime "updated_at", null: false
    t.index ["booking_type_id", "day_of_week"], name: "index_weekly_availabilities_on_booking_type_id_and_day_of_week"
    t.index ["booking_type_id"], name: "index_weekly_availabilities_on_booking_type_id"
    t.check_constraint "day_of_week >= 0 AND day_of_week <= 6", name: "weekly_availabilities_day_of_week_range"
    t.check_constraint "start_time < end_time", name: "weekly_availabilities_time_order"
  end

  add_foreign_key "availability_overrides", "booking_types"
  add_foreign_key "booking_type_origins", "booking_types"
  add_foreign_key "reservations", "booking_types"
  add_foreign_key "weekly_availabilities", "booking_types"
end
