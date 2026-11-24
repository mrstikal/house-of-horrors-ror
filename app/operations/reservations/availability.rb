module Reservations
  class Availability < Trailblazer::Operation
    INVALID_INPUT_MESSAGE = "Select a valid room and date."
    PAST_DATE_MESSAGE = "Select today or a future date."

    step :parse_input
    step :load_slots

    def parse_input(ctx, room_id:, date:, **)
      room_id = BookingSlots.parse_id(room_id)
      date = BookingSlots.parse_date(date)

      if room_id && date
        ctx[:room_id] = room_id
        ctx[:date] = date
        true
      else
        ctx[:code] = :invalid_input
        ctx[:messages] = [ INVALID_INPUT_MESSAGE ]
        false
      end
    end

    def load_slots(ctx, **)
      now = Time.current

      if ctx[:date] < now.utc.to_date
        ctx[:code] = :invalid_input
        ctx[:messages] = [ PAST_DATE_MESSAGE ]
        return false
      end

      room = Room.find_by(id: ctx[:room_id])
      unless room
        ctx[:code] = :not_found
        ctx[:messages] = [ Reservations::Booking::ROOM_NOT_FOUND_MESSAGE ]
        return false
      end

      day_start = Time.utc(ctx[:date].year, ctx[:date].month, ctx[:date].day)
      counts = Reservations::Occupancy.counts(
        room_id: room.id,
        start_at: day_start,
        end_at: day_start + 1.day
      )

      ctx[:slots] = BookingSlots::HOURS.filter_map do |hour|
        start_at, end_at = BookingSlots.interval(ctx[:date], hour)
        next unless start_at.utc > now.utc

        remaining = room.capacity - counts.fetch(start_at, 0)
        next unless remaining.positive?

        {
          start_hour: hour,
          start_datetime: start_at,
          end_datetime: end_at,
          label: format("%02d:00-%02d:00 UTC", hour, hour + 1),
          remaining: remaining,
          nearly_full: remaining == 1 && room.capacity > 1
        }
      end

      true
    end
  end
end
