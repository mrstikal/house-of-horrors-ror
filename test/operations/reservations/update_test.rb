require "test_helper"
require_relative "../../support/committed_test_data"

class UpdateTest < ActiveSupport::TestCase
  include CommittedTestData

  setup do
    travel_to Time.utc(2026, 11, 23, 12, 0, 0)
    @time_frozen = true
  end

  teardown do
    travel_back if @time_frozen
  end

  test "saves an unchanged slot at capacity" do
    room = commit_room!(capacity: 1, name: "Unchanged Room")
    date = future_date
    reservation = commit_reservation!(room: room, **slot(date, 1))

    result = update_reservation(reservation: reservation, room: room, date: date, hour: 1)

    assert result.success?
    assert_equal reservation.id, result[:record].id
    assert_equal room.id, result[:record].room_id
    assert_equal BookingSlots.interval(date, 1).first, result[:record].start_datetime.utc
    assert_equal 1, occupancy(room, date, 1)
    assert_equal 1, Reservation.where(room_id: room.id).count
  end

  test "refuses a move to a full slot in the same room" do
    room = commit_room!(capacity: 1, name: "Same Room Full")
    date = future_date
    moving = commit_reservation!(room: room, **slot(date, 1))
    staying = commit_reservation!(room: room, **slot(date, 2))

    result = update_reservation(reservation: moving, room: room, date: date, hour: 2)

    refute result.success?
    assert_equal :slot_full, result[:code]
    assert_includes result[:messages], "This slot has just filled up. Select another time."
    assert_moved_nowhere(moving, room, date, 1)
    assert_equal room.id, staying.reload.room_id
    assert_equal 1, occupancy(room, date, 1)
    assert_equal 1, occupancy(room, date, 2)
    assert_equal 2, Reservation.where(room_id: room.id).count
  end

  test "refuses a move into a full different room" do
    source = commit_room!(capacity: 1, name: "Full Source Room")
    target = commit_room!(capacity: 1, name: "Full Target Room")
    date = future_date
    moving = commit_reservation!(room: source, **slot(date, 1))
    occupant = commit_reservation!(room: target, **slot(date, 1))

    result = update_reservation(reservation: moving, room: target, date: date, hour: 1)

    refute result.success?
    assert_equal :slot_full, result[:code]
    assert_moved_nowhere(moving, source, date, 1)
    assert_equal target.id, occupant.reload.room_id
    assert_equal 1, occupancy(source, date, 1)
    assert_equal 1, occupancy(target, date, 1)
    assert_equal 2, Reservation.where(room_id: [ source.id, target.id ]).count
  end

  test "moves to a free slot and releases the source place" do
    room = commit_room!(capacity: 2, name: "Move Room")
    date = future_date
    moving = commit_reservation!(room: room, **slot(date, 1))
    commit_reservation!(room: room, **slot(date, 1))

    result = update_reservation(reservation: moving, room: room, date: date, hour: 2)

    assert result.success?
    assert_equal BookingSlots.interval(date, 2).first, result[:record].start_datetime.utc
    assert_equal 1, occupancy(room, date, 1)
    assert_equal 1, occupancy(room, date, 2)
  end

  test "moves to a free slot in another room" do
    source = commit_room!(capacity: 1, name: "Cross Source Room")
    target = commit_room!(capacity: 2, name: "Cross Target Room")
    date = future_date
    moving = commit_reservation!(room: source, **slot(date, 1))

    result = update_reservation(reservation: moving, room: target, date: date, hour: 2)

    assert result.success?
    assert_equal target.id, result[:record].room_id
    assert_equal 0, occupancy(source, date, 1)
    assert_equal 1, occupancy(target, date, 2)
  end

  test "rejects an elapsed original without mutation" do
    room = nil
    reservation = nil
    historical_date = Date.new(2026, 11, 23)

    travel_to Time.utc(2026, 11, 22, 12, 0, 0) do
      room = commit_room!(capacity: 2, name: "Elapsed Room")
      reservation = commit_reservation!(room: room, **slot(historical_date, 1))
    end

    result = update_reservation(reservation: reservation, room: room, date: future_date, hour: 2)

    refute result.success?
    assert_equal :invalid_input, result[:code]
    assert_includes result[:messages], "Select a slot that has not started."
    assert_moved_nowhere(reservation, room, historical_date, 1)
    assert_equal 1, occupancy(room, historical_date, 1)
    assert_equal 0, occupancy(room, future_date, 2)
  end

  test "rejects a move into an elapsed slot without mutation" do
    room = commit_room!(capacity: 2, name: "Elapsed Target Room")
    date = future_date
    reservation = commit_reservation!(room: room, **slot(date, 1))
    elapsed_date = Time.current.to_date

    result = update_reservation(reservation: reservation, room: room, date: elapsed_date, hour: 1)

    refute result.success?
    assert_equal :invalid_input, result[:code]
    assert_includes result[:messages], "Select a slot that has not started."
    assert_moved_nowhere(reservation, room, date, 1)
    assert_equal 1, occupancy(room, date, 1)
    assert_equal 0, occupancy(room, elapsed_date, 1)
  end

  test "rejects missing reservation and room ids without mutation" do
    room = commit_room!(capacity: 1, name: "Missing Update Room")
    date = future_date
    reservation = commit_reservation!(room: room, **slot(date, 1))

    missing_reservation = Reservations::Update.call(
      id: 999_999, room_id: room.id, date: date.iso8601, start_hour: 2
    )
    refute missing_reservation.success?
    assert_equal :not_found, missing_reservation[:code]
    assert_includes missing_reservation[:messages], "Reservation not found."

    missing_room = Reservations::Update.call(
      id: reservation.id, room_id: 999_999, date: date.iso8601, start_hour: 2
    )
    refute missing_room.success?
    assert_equal :not_found, missing_room[:code]
    assert_includes missing_room[:messages], "Room not found."

    assert_moved_nowhere(reservation, room, date, 1)
    assert_equal 1, occupancy(room, date, 1)
    assert_equal 0, occupancy(room, date, 2)
    assert_equal 1, Reservation.where(room_id: room.id).count
  end

  test "rejects malformed input without mutation" do
    room = commit_room!(capacity: 1, name: "Malformed Update Room")
    date = future_date
    reservation = commit_reservation!(room: room, **slot(date, 1))

    [
      { id: "abc", room_id: room.id, date: date.iso8601, start_hour: 1 },
      { id: reservation.id, room_id: room.id, date: "not-a-date", start_hour: 1 },
      { id: reservation.id, room_id: room.id, date: date.iso8601, start_hour: 7 }
    ].each do |input|
      result = Reservations::Update.call(**input)

      refute result.success?
      assert_equal :invalid_input, result[:code]
      assert_includes result[:messages], "Select a valid reservation, room, date and hour."
    end

    assert_moved_nowhere(reservation, room, date, 1)
    assert_equal 1, occupancy(room, date, 1)
  end

  test "maps guard contention to busy for update and destroy" do
    room = commit_room!(capacity: 2, name: "Busy Room")
    date = future_date
    reservation = commit_reservation!(room: room, **slot(date, 1))

    booking_write = BookingWrite.singleton_class
    booking_write.alias_method :__guarded_with_lock, :with_lock
    BookingWrite.define_singleton_method(:with_lock) { |&_block| raise BookingWrite::Busy }

    begin
      update_result = update_reservation(reservation: reservation, room: room, date: date, hour: 2)
      destroy_result = Reservations::Destroy.call(id: reservation.id)
    ensure
      booking_write.alias_method :with_lock, :__guarded_with_lock
      booking_write.remove_method :__guarded_with_lock
    end

    refute update_result.success?
    assert_equal :busy, update_result[:code]
    assert_includes update_result[:messages], "The booking system is busy. Try again."

    refute destroy_result.success?
    assert_equal :busy, destroy_result[:code]
    assert_includes destroy_result[:messages], "The booking system is busy. Try again."

    assert_moved_nowhere(reservation, room, date, 1)
    assert_equal 1, Reservation.where(room_id: room.id).count
  end

  private

  def update_reservation(reservation:, room:, date:, hour:)
    Reservations::Update.call(
      id: reservation.id,
      room_id: room.id,
      date: date.iso8601,
      start_hour: hour
    )
  end

  def slot(date, hour)
    start_at, end_at = BookingSlots.interval(date, hour)

    { start_at: start_at, end_at: end_at }
  end

  def occupancy(room, date, hour)
    start_at, = BookingSlots.interval(date, hour)
    Reservation.where(room_id: room.id, start_datetime: start_at).count
  end

  def assert_moved_nowhere(reservation, room, date, hour)
    start_at, end_at = BookingSlots.interval(date, hour)
    reservation.reload

    assert_equal room.id, reservation.room_id
    assert_equal start_at, reservation.start_datetime.utc
    assert_equal end_at, reservation.end_datetime.utc
  end

  def future_date
    Time.current.to_date + 1
  end
end
