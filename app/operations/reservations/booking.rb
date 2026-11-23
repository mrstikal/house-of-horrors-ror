module Reservations
  module Booking
    def self.parse(room_id:, date:, start_hour:)
      room_id = BookingSlots.parse_id(room_id)
      date = BookingSlots.parse_date(date)
      start_hour = BookingSlots.parse_hour(start_hour)

      return nil unless room_id && date && start_hour

      { room_id: room_id, date: date, start_hour: start_hour }
    end

    def self.commit(action:, input:, id: nil)
      case action
      when :create
        raise ArgumentError, "Create does not accept an id" if id

        commit_create(input)
      else
        raise ArgumentError, "Unsupported booking action: #{action.inspect}"
      end
    end

    def self.commit_create(input)
      BookingWrite.with_lock do
        room = Room.find_by(id: input[:room_id])
        next failure(:not_found, [ "Room not found." ]) unless room

        start_at, end_at = BookingSlots.interval(input[:date], input[:start_hour])
        reservation = Reservation.new(room: room, start_datetime: start_at, end_datetime: end_at)

        unless reservation.valid?
          next failure(:invalid_input, reservation.errors.full_messages)
        end

        if Occupancy.count(room_id: room.id, start_at: start_at) >= room.capacity
          next failure(:slot_full, [ "This slot has just filled up. Select another time." ])
        end

        reservation.save!
        { ok: true, record: reservation, code: nil, messages: [] }
      end
    rescue BookingWrite::Busy
      failure(:busy, [ "The booking system is busy. Try again." ])
    rescue ActiveRecord::RecordInvalid => error
      failure(:invalid_input, error.record.errors.full_messages)
    end

    def self.failure(code, messages)
      { ok: false, record: nil, code: code, messages: messages }
    end

    private_class_method :commit_create, :failure
  end
end
