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

ActiveRecord::Schema[8.1].define(version: 2026_11_24_170300) do
  create_table "active_storage_attachments", charset: "utf8mb4", collation: "utf8mb4_0900_bin", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", charset: "utf8mb4", collation: "utf8mb4_0900_bin", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", charset: "utf8mb4", collation: "utf8mb4_0900_bin", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

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
    t.string "image_key", limit: 32
    t.string "seed_key", limit: 32
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "image_blob_id"
    t.index ["image_blob_id"], name: "index_rooms_on_image_blob_id"
    t.index ["name"], name: "index_rooms_on_name", unique: true
    t.index ["seed_key"], name: "index_rooms_on_seed_key", unique: true
    t.check_constraint "(`image_key` is null) <> (`image_blob_id` is null)", name: "rooms_exactly_one_image_reference"
    t.check_constraint "`capacity` > 0", name: "rooms_capacity_positive"
  end

  create_table "users", charset: "utf8mb4", collation: "utf8mb4_0900_bin", force: :cascade do |t|
    t.string "email_address", limit: 254, null: false
    t.string "password_digest", null: false
    t.string "role", limit: 8, default: "guest", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
    t.check_constraint "`role` in (_utf8mb4'guest',_utf8mb4'admin')", name: "users_role_valid"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "reservations", "rooms"
  add_foreign_key "rooms", "active_storage_blobs", column: "image_blob_id"
end
