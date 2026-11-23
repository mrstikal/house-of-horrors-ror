class CreateRooms < ActiveRecord::Migration[8.1]
  def change
    create_table :rooms do |t|
      t.string :name, limit: 120, null: false
      t.text :description, null: false
      t.integer :capacity, null: false
      t.string :image_key, limit: 32, null: false
      t.string :seed_key, limit: 32

      t.timestamps
    end

    add_index :rooms, :name, unique: true
    add_index :rooms, :seed_key, unique: true
    add_check_constraint :rooms, "capacity > 0", name: "rooms_capacity_positive"
  end
end
