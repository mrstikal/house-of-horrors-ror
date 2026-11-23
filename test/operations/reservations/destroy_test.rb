require "test_helper"
require_relative "../../support/committed_test_data"

class DestroyTest < ActiveSupport::TestCase
  include CommittedTestData

  setup do
    travel_to Time.utc(2026, 11, 23, 12, 0, 0)
    @time_frozen = true
  end

  teardown do
    travel_back if @time_frozen
  end

  test "deletes a future reservation and leaves its sibling" do
    room = commit_room!(capacity: 2, name: "Future Delete Room")
    date = future_date
    reservation = commit_reservation!(room: room, **slot(date, 1))
    sibling = commit_reservation!(room: room, **slot(date, 1))

    result = Reservations::Destroy.call(id: reservation.id)

    assert result.success?
    assert_equal reservation.id, result[:record].id
    assert result[:record].destroyed?
    refute Reservation.exists?(reservation.id)
    assert Reservation.exists?(sibling.id)
    assert_equal 1, Reservation.where(room_id: room.id).count
  end

  test "deletes a historical reservation" do
    room = nil
    reservation = nil

    travel_to Time.utc(2026, 11, 21, 12, 0, 0) do
      room = commit_room!(capacity: 2, name: "History Delete Room")
      reservation = commit_reservation!(room: room, **slot(Date.new(2026, 11, 22), 1))
    end

    assert_equal 1, Reservation.where(room_id: room.id).count

    result = Reservations::Destroy.call(id: reservation.id)

    assert result.success?
    refute Reservation.exists?(reservation.id)
    assert_equal 0, Reservation.where(room_id: room.id).count
  end

  test "rejects an unknown reservation id without mutation" do
    room = commit_room!(capacity: 2, name: "Unknown Delete Room")
    date = future_date
    commit_reservation!(room: room, **slot(date, 1))
    before = Reservation.where(room_id: room.id).count

    result = Reservations::Destroy.call(id: 999_999)

    refute result.success?
    assert_equal :not_found, result[:code]
    assert_includes result[:messages], "Reservation not found."
    assert_equal before, Reservation.where(room_id: room.id).count
  end

  test "rejects a malformed reservation id without mutation" do
    room = commit_room!(capacity: 2, name: "Malformed Delete Room")
    date = future_date
    reservation = commit_reservation!(room: room, **slot(date, 1))

    result = Reservations::Destroy.call(id: "abc")

    refute result.success?
    assert_equal :invalid_input, result[:code]
    assert_includes result[:messages], "Select a valid reservation."
    assert Reservation.exists?(reservation.id)
  end

  private

  def slot(date, hour)
    start_at, end_at = BookingSlots.interval(date, hour)

    { start_at: start_at, end_at: end_at }
  end

  def future_date
    Time.current.to_date + 1
  end
end
