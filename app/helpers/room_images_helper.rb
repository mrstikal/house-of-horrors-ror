module RoomImagesHelper
  def room_image_url(room)
    if room.image_blob_id
      room_photo_path(room.image_blob_id)
    else
      asset_path(RoomImages.path_for(room.image_key))
    end
  end
end
