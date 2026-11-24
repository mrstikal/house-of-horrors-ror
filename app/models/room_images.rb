module RoomImages
  BUNDLED = {
    "basement" => "house_of_horrors/room1.jpg",
    "bathroom" => "house_of_horrors/room2.jpg",
    "kitchen" => "house_of_horrors/room3.jpg",
    "attic" => "house_of_horrors/room4.jpg"
  }.freeze

  UPLOAD_MIME_TYPES = %w[image/png image/jpeg].freeze
  UPLOAD_BYTE_RANGE = 1..2.megabytes

  def self.keys
    BUNDLED.keys
  end

  def self.path_for(key)
    BUNDLED.fetch(key)
  end

  def self.uploads
    ActiveStorage::Blob.where(
      service_name: "room_images",
      content_type: UPLOAD_MIME_TYPES,
      byte_size: UPLOAD_BYTE_RANGE
    )
  end
end
