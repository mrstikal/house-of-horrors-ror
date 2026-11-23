module Reservations
  class Destroy < Trailblazer::Operation
    step :parse_input
    step :delete_booking

    def parse_input(ctx, id:, **)
      if (id = BookingSlots.parse_id(id))
        ctx[:id] = id
        true
      else
        ctx[:code] = :invalid_input
        ctx[:messages] = [ "Select a valid reservation." ]
        false
      end
    end

    def delete_booking(ctx, **)
      outcome = Reservations::Booking.commit(action: :destroy, input: nil, id: ctx[:id])

      ctx[:record] = outcome[:record]
      ctx[:code] = outcome[:code]
      ctx[:messages] = outcome[:messages]

      outcome[:ok]
    end
  end
end
