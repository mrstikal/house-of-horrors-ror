require "test_helper"

class AvailabilityTest < ActiveSupport::TestCase
  setup do
    travel_to Time.utc(2026, 11, 23, 12, 0, 0)
    @time_frozen = true
    @room = Room.create!(
      name: "Availability Room",
      description: "A room used for availability tests.",
      capacity: 2,
      image_key: "basement"
    )
  end

  teardown do
    travel_back if @time_frozen
  end

  test "returns future slots with aggregate remaining places" do
    book(@room, future_date, 1)

    result = call_availability

    assert result.success?
    assert_equal @room.id, result[:room_id]
    assert_equal future_date, result[:date]
    assert_equal (1..6).to_a, result[:slots].map { |slot| slot[:start_hour] }

    first = result[:slots].first
    assert_equal [ :start_hour, :start_datetime, :end_datetime, :label, :remaining, :nearly_full ].sort,
      first.keys.sort
    assert_equal 1, first[:remaining]
    assert first[:nearly_full]
    assert_equal "01:00-02:00 UTC", first[:label]
    assert_equal BookingSlots.interval(future_date, 1).first, first[:start_datetime]
    assert_equal BookingSlots.interval(future_date, 1).last, first[:end_datetime]

    second = result[:slots].second
    assert_equal 2, second[:remaining]
    refute second[:nearly_full]
    assert result[:slots].none? { |slot| slot.key?(:id) || slot.key?(:reservation_id) }
  end

  test "does not mark an empty one-person room as nearly full" do
    room = create_room(capacity: 1, name: "One Person Availability Room")

    result = call_availability(room_id: room.id)

    assert result.success?
    assert_equal 1, result[:slots].first[:remaining]
    refute result[:slots].first[:nearly_full]
  end

  test "omits a full slot" do
    room = create_room(capacity: 1, name: "Full Availability Room")
    book(room, future_date, 1)

    result = call_availability(room_id: room.id)

    assert result.success?
    assert_equal (2..6).to_a, result[:slots].map { |slot| slot[:start_hour] }
  end

  test "returns an empty slot list when every hour is full" do
    room = create_room(capacity: 1, name: "No Availability Room")

    BookingSlots::HOURS.each { |hour| book(room, future_date, hour) }

    result = call_availability(room_id: room.id)

    assert result.success?
    assert_equal [], result[:slots]
  end

  test "suppresses started slots on the same day" do
    travel_to Time.utc(2026, 11, 23, 1, 30, 0) do
      result = call_availability(date: Date.new(2026, 11, 23))

      assert result.success?
      assert_equal (2..6).to_a, result[:slots].map { |slot| slot[:start_hour] }
    end
  end

  test "rejects a past date" do
    result = call_availability(date: Time.current.to_date - 1)

    refute result.success?
    assert_equal :invalid_input, result[:code]
    assert_includes result[:messages], "Select today or a future date."
  end

  test "rejects malformed room and date input" do
    [
      { room_id: "abc", date: future_date.iso8601 },
      { room_id: @room.id, date: "not-a-date" },
      { room_id: nil, date: future_date.iso8601 },
      { room_id: @room.id, date: nil }
    ].each do |input|
      result = Reservations::Availability.call(**input)

      refute result.success?
      assert_equal :invalid_input, result[:code]
      assert_includes result[:messages], "Select a valid room and date."
    end
  end

  test "returns not_found for a well-formed missing room" do
    result = call_availability(room_id: 999_999)

    refute result.success?
    assert_equal :not_found, result[:code]
    assert_includes result[:messages], "Room not found."
  end

  private

  def call_availability(room_id: @room.id, date: future_date)
    Reservations::Availability.call(
      room_id: room_id,
      date: date.is_a?(Date) ? date.iso8601 : date
    )
  end

  def book(room, date, hour)
    start_at, end_at = BookingSlots.interval(date, hour)
    Reservation.create!(room: room, start_datetime: start_at, end_datetime: end_at)
  end

  def create_room(capacity:, name:)
    Room.create!(
      name: name,
      description: "A room used for availability tests.",
      capacity: capacity,
      image_key: "bathroom"
    )
  end

  def future_date
    Time.current.to_date + 1
  end
end
