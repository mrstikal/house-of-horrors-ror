module Rooms
  class Write
    ALLOWED_ATTRIBUTES = %i[name description capacity image_key].freeze
    NOT_FOUND_MESSAGE = "Room not found."
    ROOM_HAS_RESERVATIONS_MESSAGE = "Delete this room's reservations before deleting the room."
    BUSY_MESSAGE = "The booking system is busy. Try again."
    DUPLICATE_NAME_MESSAGE = "Name has already been taken."

    def self.call(action:, id: nil, attributes: {})
      new.call(action: action, id: id, attributes: attributes)
    end

    def call(action:, id: nil, attributes: {})
      case action
      when :create
        create(attributes)
      when :update
        update(id, attributes)
      when :destroy
        destroy(id)
      else
        raise ArgumentError, "Unsupported room action: #{action.inspect}"
      end
    end

    private

    def create(attributes)
      guarded do
        room = Room.new(room_attributes(attributes))

        unless room.valid?
          next failure(:invalid_input, room.errors.full_messages)
        end

        room.save!
        success(room)
      end
    end

    def update(id, attributes)
      guarded do
        room = Room.find_by(id: id)
        next failure(:not_found, [ NOT_FOUND_MESSAGE ]) unless room

        room.assign_attributes(room_attributes(attributes))

        unless room.valid?
          next failure(:invalid_input, room.errors.full_messages)
        end

        peak = Reservations::Occupancy.peak(room_id: room.id)
        if room.capacity < peak
          next failure(:capacity_below_bookings, [
            format("Capacity cannot be lower than the existing peak of %d.", peak)
          ])
        end

        room.save!
        success(room)
      end
    end

    def destroy(id)
      guarded do
        room = Room.find_by(id: id)
        next failure(:not_found, [ NOT_FOUND_MESSAGE ]) unless room

        if Reservation.exists?(room_id: room.id)
          next failure(:room_has_reservations, [ ROOM_HAS_RESERVATIONS_MESSAGE ])
        end

        room.destroy!
        success(room)
      end
    end

    def guarded
      BookingWrite.with_lock { yield }
    rescue BookingWrite::Busy
      failure(:busy, [ BUSY_MESSAGE ])
    rescue ActiveRecord::RecordInvalid => error
      failure(:invalid_input, error.record.errors.full_messages)
    rescue ActiveRecord::RecordNotUnique
      failure(:invalid_input, [ DUPLICATE_NAME_MESSAGE ])
    rescue ActiveRecord::RecordNotDestroyed
      failure(:room_has_reservations, [ ROOM_HAS_RESERVATIONS_MESSAGE ])
    end

    def room_attributes(attributes)
      values = attributes.respond_to?(:permit) ? attributes.permit(*ALLOWED_ATTRIBUTES) : (attributes || {})

      values.to_h.symbolize_keys.slice(*ALLOWED_ATTRIBUTES)
    end

    def success(record)
      { ok: true, record: record, code: nil, messages: [] }
    end

    def failure(code, messages)
      { ok: false, record: nil, code: code, messages: messages }
    end
  end
end
