class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string :email_address, limit: 254, null: false
      t.string :password_digest, null: false
      t.string :role, limit: 8, null: false, default: "guest"

      t.timestamps
    end

    add_index :users, :email_address, unique: true
    add_check_constraint :users, "role IN ('guest', 'admin')", name: "users_role_valid"
  end
end
