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

ActiveRecord::Schema[8.1].define(version: 2026_11_23_184833) do
  create_table "booking_write_locks", id: :integer, charset: "utf8mb4", collation: "utf8mb4_0900_bin", force: :cascade do |t|
    t.integer "token", null: false
  end

  create_table "reservations", charset: "utf8mb4", collation: "utf8mb4_0900_bin", force: :cascade do |t|
    t.bigint "room_id", null: false
    t.datetime "start_datetime", null: false
    t.datetime "end_datetime", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["room_id", "start_datetime"], name: "index_reservations_on_room_id_and_start_datetime"
    t.index ["start_datetime"], name: "index_reservations_on_start_datetime"
    t.check_constraint "`end_datetime` > `start_datetime`", name: "reservations_end_after_start"
  end

  create_table "rooms", charset: "utf8mb4", collation: "utf8mb4_0900_bin", force: :cascade do |t|
    t.string "name", limit: 120, null: false
    t.text "description", null: false
    t.integer "capacity", null: false
    t.string "image_key", limit: 32, null: false
    t.string "seed_key", limit: 32
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_rooms_on_name", unique: true
    t.index ["seed_key"], name: "index_rooms_on_seed_key", unique: true
    t.check_constraint "`capacity` > 0", name: "rooms_capacity_positive"
  end

  add_foreign_key "reservations", "rooms"
end
