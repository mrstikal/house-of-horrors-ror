module Reservations
  module Occupancy
    def self.count(room_id:, start_at:, excluding_id: nil)
      scope = Reservation.where(room_id: room_id, start_datetime: start_at)
      scope = scope.where.not(id: excluding_id) if excluding_id
      scope.count
    end

    def self.counts(room_id:, start_at:, end_at:)
      Reservation
        .where(room_id: room_id, start_datetime: start_at...end_at)
        .group(:start_datetime)
        .count
        .transform_keys { |start| start.utc }
    end
  end
end
