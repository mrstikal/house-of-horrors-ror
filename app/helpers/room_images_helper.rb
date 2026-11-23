module RoomImagesHelper
  def room_image_url(room)
    asset_path(RoomImages.path_for(room.image_key))
  end
end
