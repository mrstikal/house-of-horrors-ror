module Reservations
  module Booking
    ROOM_NOT_FOUND_MESSAGE = "Room not found."
    RESERVATION_NOT_FOUND_MESSAGE = "Reservation not found."
    SLOT_FULL_MESSAGE = "This slot has just filled up. Select another time."
    BUSY_MESSAGE = "The booking system is busy. Try again."

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
      when :update
        raise ArgumentError, "Update requires an id" unless id
        raise ArgumentError, "Update requires input" unless input

        commit_update(id, input)
      when :destroy
        raise ArgumentError, "Destroy does not accept input" if input
        raise ArgumentError, "Destroy requires an id" unless id

        commit_destroy(id)
      else
        raise ArgumentError, "Unsupported booking action: #{action.inspect}"
      end
    end

    def self.commit_create(input)
      BookingWrite.with_lock do
        room = Room.find_by(id: input[:room_id])
        next failure(:not_found, [ ROOM_NOT_FOUND_MESSAGE ]) unless room

        start_at, end_at = BookingSlots.interval(input[:date], input[:start_hour])
        reservation = Reservation.new(room: room, start_datetime: start_at, end_datetime: end_at)

        unless reservation.valid?
          next failure(:invalid_input, reservation.errors.full_messages)
        end

        if slot_full?(room, start_at)
          next failure(:slot_full, [ SLOT_FULL_MESSAGE ])
        end

        reservation.save!
        success(reservation)
      end
    rescue BookingWrite::Busy
      failure(:busy, [ BUSY_MESSAGE ])
    rescue ActiveRecord::RecordInvalid => error
      failure(:invalid_input, error.record.errors.full_messages)
    end

    def self.commit_update(id, input)
      BookingWrite.with_lock do
        reservation = Reservation.find_by(id: id)
        next failure(:not_found, [ RESERVATION_NOT_FOUND_MESSAGE ]) unless reservation

        if reservation.start_datetime.utc <= Time.current.utc
          next failure(:invalid_input, [ Reservation::STARTED_MESSAGE ])
        end

        room = Room.find_by(id: input[:room_id])
        next failure(:not_found, [ ROOM_NOT_FOUND_MESSAGE ]) unless room

        start_at, end_at = BookingSlots.interval(input[:date], input[:start_hour])
        reservation.room = room
        reservation.start_datetime = start_at
        reservation.end_datetime = end_at

        unless reservation.valid?
          next failure(:invalid_input, reservation.errors.full_messages)
        end

        if slot_full?(room, start_at, excluding_id: reservation.id)
          next failure(:slot_full, [ SLOT_FULL_MESSAGE ])
        end

        reservation.save!
        success(reservation)
      end
    rescue BookingWrite::Busy
      failure(:busy, [ BUSY_MESSAGE ])
    rescue ActiveRecord::RecordInvalid => error
      failure(:invalid_input, error.record.errors.full_messages)
    end

    def self.commit_destroy(id)
      BookingWrite.with_lock do
        reservation = Reservation.find_by(id: id)
        next failure(:not_found, [ RESERVATION_NOT_FOUND_MESSAGE ]) unless reservation

        reservation.destroy!
        success(reservation)
      end
    rescue BookingWrite::Busy
      failure(:busy, [ BUSY_MESSAGE ])
    end

    def self.slot_full?(room, start_at, excluding_id: nil)
      Occupancy.count(room_id: room.id, start_at: start_at, excluding_id: excluding_id) >= room.capacity
    end

    def self.success(record)
      { ok: true, record: record, code: nil, messages: [] }
    end

    def self.failure(code, messages)
      { ok: false, record: nil, code: code, messages: messages }
    end

    private_class_method :commit_create, :commit_update, :commit_destroy, :slot_full?, :success, :failure
  end
end
