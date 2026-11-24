class AddUploadedImagesToRooms < ActiveRecord::Migration[8.1]
  def change
    change_column_null :rooms, :image_key, true

    add_reference :rooms, :image_blob,
      foreign_key: { to_table: :active_storage_blobs, on_delete: :restrict },
      index: true

    add_check_constraint :rooms, "(image_key IS NULL) <> (image_blob_id IS NULL)",
      name: "rooms_exactly_one_image_reference"
  end
end
