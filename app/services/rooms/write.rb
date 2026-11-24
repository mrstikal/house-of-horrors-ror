module Rooms
  class Write
    ALLOWED_ATTRIBUTES = %i[name description capacity image_choice].freeze
    NOT_FOUND_MESSAGE = "Room not found."
    ROOM_HAS_RESERVATIONS_MESSAGE = "Delete this room's reservations before deleting the room."
    BUSY_MESSAGE = "The booking system is busy. Try again."
    DUPLICATE_NAME_MESSAGE = "Name has already been taken."
    INVALID_IMAGE_MESSAGE = "Select a valid room image."

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
        values = room_attributes(attributes)
        room = Room.new(room_fields(values))
        next failure(:invalid_input, [ INVALID_IMAGE_MESSAGE ]) unless apply_image_choice(room, values)

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

        values = room_attributes(attributes)
        room.assign_attributes(room_fields(values))
        next failure(:invalid_input, [ INVALID_IMAGE_MESSAGE ]) unless apply_image_choice(room, values)

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

    def room_fields(values)
      values.slice(:name, :description, :capacity)
    end

    def apply_image_choice(room, values)
      return true unless values.key?(:image_choice)

      choice = values[:image_choice]
      return false unless choice.is_a?(String)

      kind, value = choice.split(":", 2)
      return false if value.blank?

      case kind
      when "bundled"
        return false unless RoomImages.keys.include?(value)

        room.image_key = value
        room.image_blob_id = nil
      when "upload"
        blob_id = BookingSlots.parse_id(value)
        blob = blob_id && RoomImages.uploads.find_by(id: blob_id)
        return false unless blob

        room.image_key = nil
        room.image_blob_id = blob.id
      else
        return false
      end

      true
    end

    def success(record)
      { ok: true, record: record, code: nil, messages: [] }
    end

    def failure(code, messages)
      { ok: false, record: nil, code: code, messages: messages }
    end
  end
end
