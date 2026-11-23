require "test_helper"

class ReservationTest < ActiveSupport::TestCase
  setup do
    travel_to Time.utc(2026, 11, 23, 1, 0, 0)
    @room = create_room
    @other_room = create_room(
      name: "The Bathroom That Judges You",
      description: "The mirror looks back.",
      capacity: 1,
      image_key: "bathroom"
    )
  end

  teardown do
    travel_back
  end

  test "accepts a canonical future slot" do
    reservation = build_slot_reservation(room: @room, date: Date.new(2026, 11, 24), hour: 1)

    assert reservation.valid?
    assert reservation.save
  end

  test "requires a room association" do
    reservation = build_slot_reservation(room: nil, date: Date.new(2026, 11, 24), hour: 1)

    refute reservation.valid?
    assert reservation.errors[:room].any?
  end

  test "rejects a schedule that is not exactly one canonical hour" do
    reservation = build_reservation(
      room: @room,
      start_at: Time.utc(2026, 11, 24, 1),
      end_at: Time.utc(2026, 11, 24, 3)
    )

    refute reservation.valid?
    assert_includes reservation.errors[:base], "Select an hourly slot from 01:00 to 07:00 UTC."
  end

  test "rejects off-minute and subsecond starts" do
    off_minute = build_reservation(
      room: @room,
      start_at: Time.utc(2026, 11, 24, 1, 30),
      end_at: Time.utc(2026, 11, 24, 2, 30)
    )
    subsecond = build_reservation(
      room: @room,
      start_at: Time.utc(2026, 11, 24, 1, 0, 0, 500_000),
      end_at: Time.utc(2026, 11, 24, 2, 0, 0, 500_000)
    )

    refute off_minute.valid?
    assert_includes off_minute.errors[:base], "Select an hourly slot from 01:00 to 07:00 UTC."
    refute subsecond.valid?
    assert_includes subsecond.errors[:base], "Select an hourly slot from 01:00 to 07:00 UTC."
  end

  test "rejects midnight and 07:00 starts" do
    midnight = build_reservation(
      room: @room,
      start_at: Time.utc(2026, 11, 24, 0),
      end_at: Time.utc(2026, 11, 24, 1)
    )
    seven = build_reservation(
      room: @room,
      start_at: Time.utc(2026, 11, 24, 7),
      end_at: Time.utc(2026, 11, 24, 8)
    )

    refute midnight.valid?
    assert_includes midnight.errors[:base], "Select an hourly slot from 01:00 to 07:00 UTC."
    refute seven.valid?
    assert_includes seven.errors[:base], "Select an hourly slot from 01:00 to 07:00 UTC."
  end

  test "accepts 01:00 and 06:00 starts" do
    first = build_slot_reservation(room: @room, date: Date.new(2026, 11, 24), hour: 1)
    last = build_slot_reservation(room: @room, date: Date.new(2026, 11, 24), hour: 6)

    assert first.valid?
    assert last.valid?
  end

  test "refuses exactly-now and past starts on create" do
    exactly_now = build_reservation(
      room: @room,
      start_at: Time.utc(2026, 11, 23, 1),
      end_at: Time.utc(2026, 11, 23, 2)
    )
    past = build_reservation(
      room: @room,
      start_at: Time.utc(2026, 11, 22, 1),
      end_at: Time.utc(2026, 11, 22, 2)
    )

    refute exactly_now.valid?
    assert_includes exactly_now.errors[:base], "Select a slot that has not started."
    refute past.valid?
    assert_includes past.errors[:base], "Select a slot that has not started."
  end

  test "allows an unchanged historical reservation to be saved" do
    historical = nil
    travel_to Time.utc(2026, 11, 20, 1, 0, 0) do
      historical = create_reservation(
        room: @room,
        start_at: Time.utc(2026, 11, 21, 1),
        end_at: Time.utc(2026, 11, 21, 2)
      )
    end

    loaded = Reservation.find(historical.id)

    assert loaded.valid?
    assert loaded.save
    assert_empty loaded.errors[:base]
  end

  test "checks the future start when the room changes on an update" do
    historical = nil
    travel_to Time.utc(2026, 11, 20, 1, 0, 0) do
      historical = create_reservation(
        room: @room,
        start_at: Time.utc(2026, 11, 21, 1),
        end_at: Time.utc(2026, 11, 21, 2)
      )
    end

    loaded = Reservation.find(historical.id)
    loaded.room = @other_room

    refute loaded.valid?
    assert_includes loaded.errors[:base], "Select a slot that has not started."
  end

  test "checks the future start when the interval changes on an update" do
    reservation = create_reservation(
      room: @room,
      start_at: Time.utc(2026, 11, 24, 1),
      end_at: Time.utc(2026, 11, 24, 2)
    )
    reservation.start_datetime = Time.utc(2026, 11, 22, 1)
    reservation.end_datetime = Time.utc(2026, 11, 22, 2)

    refute reservation.valid?
    assert_includes reservation.errors[:base], "Select a slot that has not started."
  end

  test "exposes both associations" do
    reservation = create_reservation(
      room: @room,
      start_at: Time.utc(2026, 11, 24, 1),
      end_at: Time.utc(2026, 11, 24, 2)
    )

    assert_equal @room, reservation.room
    assert_includes @room.reservations, reservation
  end

  test "restricts room deletion when reservations exist" do
    create_reservation(
      room: @room,
      start_at: Time.utc(2026, 11, 24, 1),
      end_at: Time.utc(2026, 11, 24, 2)
    )

    refute @room.destroy
    assert @room.errors[:base].any?
    assert Room.exists?(@room.id)
  end

  test "rejects a reservation with a nonexistent room through the foreign key" do
    reservation = build_reservation(
      room: nil,
      start_at: Time.utc(2026, 11, 24, 1),
      end_at: Time.utc(2026, 11, 24, 2)
    )
    reservation.room_id = 999_999

    assert_raises(ActiveRecord::InvalidForeignKey) { reservation.save(validate: false) }
  end

  private

  def create_room(overrides = {})
    Room.create!({
      name: "The Basement Where Mobile Signal Goes to Die",
      description: "You walk down the stairs and your phone gives up.",
      capacity: 10,
      image_key: "basement"
    }.merge(overrides))
  end

  def build_reservation(room:, start_at:, end_at:)
    Reservation.new(room: room, start_datetime: start_at, end_datetime: end_at)
  end

  def build_slot_reservation(room:, date:, hour:)
    start_at, end_at = BookingSlots.interval(date, hour)

    build_reservation(room: room, start_at: start_at, end_at: end_at)
  end

  def create_reservation(room:, start_at:, end_at:)
    Reservation.create!(room: room, start_datetime: start_at, end_datetime: end_at)
  end
end
