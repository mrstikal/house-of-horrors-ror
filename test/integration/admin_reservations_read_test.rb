require "test_helper"
require_relative "../support/admin_session_test_helper"

class AdminReservationsReadTest < ActionDispatch::IntegrationTest
  include AdminSessionTestHelper

  ADMIN_EMAIL = "reservations-admin@example.test"
  PASSWORD = "reservations admin password"

  setup do
    travel_to Time.utc(2026, 11, 24, 12, 0, 0)
    @time_frozen = true
    @admin = User.create!(email_address: ADMIN_EMAIL, password: PASSWORD, role: "admin")
    sign_in_admin
  end

  teardown do
    travel_back if @time_frozen
  end

  test "renders the active Reservations tab and lists bookings chronologically" do
    room_a = create_room(name: "Reservation Room A")
    room_b = create_room(name: "Reservation Room B")
    date = Date.new(2026, 12, 1)
    later = create_reservation(room: room_a, date: date, hour: 2)
    earlier = create_reservation(room: room_b, date: date, hour: 1)
    same_start = create_reservation(room: room_a, date: date, hour: 1)

    get admin_reservations_path

    assert_response :success
    assert_select "nav a[aria-current='page']", text: "Reservations"
    assert_select "nav a", text: "Rooms"
    ids = css_select(".admin-reservations-table tbody tr td:last-child a").map(&:text).map(&:to_i)
    assert_equal [ earlier.id, same_start.id, later.id ], ids
    assert_select "a[href=?]", new_admin_reservation_path, text: "New reservation"
  end

  test "intersects room and UTC date filters across adjacent dates" do
    room_a = create_room(name: "Filter Room A")
    room_b = create_room(name: "Filter Room B")
    first_date = Date.new(2026, 12, 1)
    second_date = Date.new(2026, 12, 2)
    a_first = create_reservation(room: room_a, date: first_date, hour: 1)
    a_second = create_reservation(room: room_a, date: second_date, hour: 1)
    b_first = create_reservation(room: room_b, date: first_date, hour: 1)

    get admin_reservations_path, params: { room_id: room_a.id, date: first_date.iso8601 }
    assert_response :success
    assert_equal [ a_first.id ], reservation_link_ids

    get admin_reservations_path, params: { room_id: room_a.id }
    assert_response :success
    assert_equal [ a_first.id, a_second.id ], reservation_link_ids

    get admin_reservations_path, params: { date: first_date.iso8601 }
    assert_response :success
    assert_equal [ a_first.id, b_first.id ], reservation_link_ids
  end

  test "omits blank scalar filters" do
    room = create_room(name: "Blank Filter Room")
    first = create_reservation(room: room, date: Date.new(2026, 12, 1), hour: 1)
    second = create_reservation(room: room, date: Date.new(2026, 12, 2), hour: 1)

    get admin_reservations_path, params: { room_id: "", date: " " }

    assert_response :success
    assert_equal [ first.id, second.id ], reservation_link_ids
  end

  test "rejects invalid scalar filters with 422 and preserves them" do
    get admin_reservations_path, params: { room_id: "abc", date: "not-a-date" }

    assert_response :unprocessable_entity
    assert_select ".admin-error", text: "Select a valid room and UTC date filter."
    assert_select "select[name=?] option[selected][value=?]", "room_id", "abc"
    assert_select "input[name=?][value=?]", "date", "not-a-date"
    assert_select ".admin-reservations-table", count: 0
  end

  test "rejects nonscalar filters while preserving scalar ones" do
    get admin_reservations_path, params: { room_id: [ "1" ], date: { year: "2026" } }
    assert_response :unprocessable_entity
    assert_select ".admin-error", text: "Select a valid room and UTC date filter."

    get admin_reservations_path, params: { room_id: "1", date: [ "2026-12-01" ] }
    assert_response :unprocessable_entity
    assert_select "select[name=?] option[selected][value=?]", "room_id", "1"
    assert_nil css_select("input[name='date']").first["value"]
  end

  test "returns an empty state for valid filters without matches" do
    room = create_room(name: "No Match Filter Room")
    create_reservation(room: room, date: Date.new(2026, 12, 1), hour: 1)

    get admin_reservations_path, params: { date: "2026-12-05" }

    assert_response :success
    assert_select ".admin-status", text: "No reservations match these filters."
    assert_select ".admin-reservations-table", count: 0
  end

  test "shows reservation details including historical reservations" do
    room = nil
    reservation = nil
    travel_to Time.utc(2026, 11, 20, 12, 0, 0) do
      room = create_room(name: "Historical Reservation Room")
      reservation = create_reservation(room: room, date: Date.new(2026, 11, 21), hour: 1)
    end

    get admin_reservation_path(reservation)

    assert_response :success
    assert_select "h2", text: "Reservation ##{reservation.id}"
    assert_select ".admin-room-facts dd", text: room.name
    assert_select ".admin-room-facts dd", text: reservation.start_datetime.utc.iso8601
    assert_select ".admin-room-facts dd", text: reservation.end_datetime.utc.iso8601
    assert_select "a[href=?]", admin_room_path(room), text: room.name
    assert_select "a[href=?]", admin_reservations_path, text: "Back to reservations"
  end

  test "rejects anonymous reads before lookup and returns 404 for an authorized missing reservation" do
    open_session do |guest|
      guest.get admin_reservations_path
      assert_equal 403, guest.response.status

      guest.get admin_reservation_path(999_999)
      assert_equal 403, guest.response.status
    end

    get admin_reservation_path(999_999)
    assert_response :not_found
  end

  private

  def sign_in_admin
    post admin_session_path, params: {
      session: { email_address: ADMIN_EMAIL, password: PASSWORD }
    }
    assert_response :see_other
  end

  def create_room(name:, capacity: 3)
    Room.create!(
      name: name,
      description: "A room used for reservation read tests.",
      capacity: capacity,
      image_key: "basement"
    )
  end

  def create_reservation(room:, date:, hour:)
    start_at, end_at = BookingSlots.interval(date, hour)
    Reservation.create!(room: room, start_datetime: start_at, end_datetime: end_at)
  end

  def reservation_link_ids
    css_select(".admin-reservations-table tbody tr td:last-child a").map(&:text).map(&:to_i)
  end
end
