module RoomImagesHelper
  def room_image_url(room)
    if room.image_blob_id
      room_photo_path(room.image_blob_id)
    else
      asset_path(RoomImages.path_for(room.image_key))
    end
  end

  def room_image_choice(room)
    return nil unless room

    if room.image_blob_id
      "upload:#{room.image_blob_id}"
    elsif room.image_key.present?
      "bundled:#{room.image_key}"
    end
  end
end
