class HomeController < ApplicationController
  def show
    @booking_config = {
      rooms: Room.order(:id).map do |room|
        {
          id: room.id.to_s,
          name: room.name,
          description: room.description,
          capacity: room.capacity,
          image_url: helpers.room_image_url(room)
        }
      end,
      today: Time.current.utc.to_date.iso8601,
      availability_path: helpers.api_availability_path,
      reservations_path: helpers.api_reservations_path
    }
  end
end
