class CreateReservations < ActiveRecord::Migration[8.1]
  def change
    create_table :reservations do |t|
      t.references :room, null: false, foreign_key: { on_delete: :restrict }, index: false
      t.datetime :start_datetime, precision: 6, null: false
      t.datetime :end_datetime, precision: 6, null: false

      t.timestamps
    end

    add_index :reservations, [ :room_id, :start_datetime ]
    add_index :reservations, :start_datetime
    add_check_constraint :reservations, "end_datetime > start_datetime", name: "reservations_end_after_start"
  end
end
