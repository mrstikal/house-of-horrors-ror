module RoomImages
  BUNDLED = {
    "basement" => "house_of_horrors/room1.jpg",
    "bathroom" => "house_of_horrors/room2.jpg",
    "kitchen" => "house_of_horrors/room3.jpg",
    "attic" => "house_of_horrors/room4.jpg"
  }.freeze

  def self.keys
    BUNDLED.keys
  end

  def self.path_for(key)
    BUNDLED.fetch(key)
  end
end
