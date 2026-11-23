module Reservations
  class Update < Trailblazer::Operation
    step :parse_input
    step :commit_booking

    def parse_input(ctx, id:, room_id:, date:, start_hour:, **)
      id = BookingSlots.parse_id(id)
      input = Reservations::Booking.parse(room_id:, date:, start_hour:)

      if id && input
        ctx[:id] = id
        ctx[:input] = input
        true
      else
        ctx[:code] = :invalid_input
        ctx[:messages] = [ "Select a valid reservation, room, date and hour." ]
        false
      end
    end

    def commit_booking(ctx, **)
      outcome = Reservations::Booking.commit(action: :update, input: ctx[:input], id: ctx[:id])

      ctx[:record] = outcome[:record]
      ctx[:code] = outcome[:code]
      ctx[:messages] = outcome[:messages]

      outcome[:ok]
    end
  end
end
