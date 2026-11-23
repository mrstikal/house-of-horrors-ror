class CreateBookingWriteLocks < ActiveRecord::Migration[8.1]
  def change
    create_table :booking_write_locks, id: :integer do |t|
      t.integer :token, null: false
    end
  end
end
