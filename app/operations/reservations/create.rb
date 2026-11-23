module Reservations
  class Create < Trailblazer::Operation
    step :parse_input
    step :commit_booking

    def parse_input(ctx, room_id:, date:, start_hour:, **)
      input = Reservations::Booking.parse(room_id:, date:, start_hour:)

      if input
        ctx[:input] = input
        true
      else
        ctx[:code] = :invalid_input
        ctx[:messages] = [ "Select a valid room, date and hour." ]
        false
      end
    end

    def commit_booking(ctx, **)
      outcome = Reservations::Booking.commit(action: :create, input: ctx[:input])

      ctx[:record] = outcome[:record]
      ctx[:code] = outcome[:code]
      ctx[:messages] = outcome[:messages]

      outcome[:ok]
    end
  end
end
