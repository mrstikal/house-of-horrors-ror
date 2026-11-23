module Reservations
  module Occupancy
    def self.count(room_id:, start_at:, excluding_id: nil)
      scope = Reservation.where(room_id: room_id, start_datetime: start_at)
      scope = scope.where.not(id: excluding_id) if excluding_id
      scope.count
    end
  end
end
