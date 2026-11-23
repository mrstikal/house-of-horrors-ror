module CommittedTestData
  extend ActiveSupport::Concern

  included do
    self.use_transactional_tests = false

    setup do
      assert Rails.env.test?, "CommittedTestData requires the test environment"
      refute ActiveRecord::Base.connection.transaction_open?, "CommittedTestData requires no open transaction"

      @committed_room_ids = []
      @committed_reservation_ids = []
      @committed_room_sequence = 0
    end

    teardown do
      room_ids = @committed_room_ids || []
      Reservation.where(room_id: room_ids).delete_all if room_ids.any?
      Reservation.where(id: @committed_reservation_ids).delete_all if @committed_reservation_ids&.any?
      Room.where(id: room_ids).delete_all if room_ids.any?
    end
  end

  def commit_room!(overrides = {})
    @committed_room_sequence ||= 0
    @committed_room_sequence += 1

    room = Room.create!({
      name: "Committed Room #{@committed_room_sequence}",
      description: "You walk down the stairs and your phone gives up.",
      capacity: 10,
      image_key: "basement"
    }.merge(overrides))
    @committed_room_ids << room.id
    room
  end

  def commit_reservation!(room:, start_at:, end_at:)
    reservation = Reservation.create!(room: room, start_datetime: start_at, end_datetime: end_at)
    @committed_reservation_ids << reservation.id
    reservation
  end
end
