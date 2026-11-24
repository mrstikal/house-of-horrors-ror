require "test_helper"
require_relative "../support/committed_test_data"
require_relative "../support/admin_session_test_helper"

class AdminReservationsTest < ActionDispatch::IntegrationTest
  include CommittedTestData
  include AdminSessionTestHelper

  ADMIN_EMAIL = "reservation-writes-admin@example.test"
  PASSWORD = "reservation writes password"

  class BusyFailure
    def success?
      false
    end

    def [](key)
      key == :code ? :busy : [ "The booking system is busy. Try again." ]
    end
  end

  setup do
    travel_to Time.utc(2026, 11, 23, 12, 0, 0)
    @time_frozen = true
    @admin = User.create!(email_address: ADMIN_EMAIL, password: PASSWORD, role: "admin")
    sign_in_admin
  end

  teardown do
    User.where(email_address: ADMIN_EMAIL).delete_all
    travel_back if @time_frozen
  end

  test "index links to the new reservation form" do
    commit_room!(name: "Index New Link Room")

    get admin_reservations_path

    assert_response :success
    assert_select "nav a[aria-current='page']", text: "Reservations"
    assert_select "a[href=?]", new_admin_reservation_path, text: "New reservation"
    assert_select "form[action=?][method=?]", admin_reservations_path, "get"
    assert_select ".admin-reservations-table", count: 0
  end

  test "renders a new form with a UTC today default and no selected room or hour" do
    room = commit_room!(name: "New Form Room")

    get new_admin_reservation_path

    assert_response :success
    assert_select "h2", text: "New reservation"
    assert_select "form[action=?][method=?]", admin_reservations_path, "post" do
      assert_select "input[name=?][value=?]", "reservation[date]", "2026-11-23"
      assert_select "select[name=?]", "reservation[room_id]" do
        assert_select "option[value=?]", room.id.to_s, text: room.name
      end
      assert_select "select[name=?]", "reservation[start_hour]" do
        BookingSlots::HOURS.each do |hour|
          label = format("%02d:00-%02d:00 UTC", hour, hour + 1)
          assert_select "option[value=?]", hour.to_s, text: label
        end
      end
      assert_select "input[type=?][value=?]", "submit", "Create reservation"
    end
    assert_select "select[name=?] option[selected]", "reservation[room_id]", count: 0
    assert_select "select[name=?] option[selected]", "reservation[start_hour]", count: 0
  end

  test "shows a no-rooms message without a form or submit" do
    assert_equal 0, Room.count

    get new_admin_reservation_path

    assert_response :success
    assert_select ".admin-status", text: "No rooms are available. Create a room before adding a reservation."
    assert_select "form.admin-reservation-form", count: 0
    assert_select ".admin-reservations-panel input[type=?]", "submit", count: 0
    assert_select "a[href=?]", new_admin_room_path, text: "Create a room"
  end

  test "creates a reservation and ignores extra submitted fields" do
    room = commit_room!(name: "Create Form Room", capacity: 2)
    date = future_date

    post admin_reservations_path, params: {
      reservation: {
        room_id: room.id,
        date: date.iso8601,
        start_hour: 1,
        id: 999_999,
        end_datetime: "2001-01-01T00:00:00Z"
      }
    }

    assert_response :see_other
    reservation = Reservation.find_by!(
      room_id: room.id,
      start_datetime: BookingSlots.interval(date, 1).first
    )
    assert_equal admin_reservation_path(reservation), URI.parse(response.location).path
    assert_equal BookingSlots.interval(date, 1).last, reservation.end_datetime.utc

    follow_redirect!

    assert_response :success
    assert_includes response.body, "Reservation was successfully created."
    assert_select "h2", text: "Reservation ##{reservation.id}"
    assert_select "a[href=?]", edit_admin_reservation_path(reservation), text: "Edit"
    assert_select "form[action=?] input[name=?][value=?]",
      admin_reservation_path(reservation), "_method", "delete"
  end

  test "edits a reservation and moves it across rooms" do
    source = commit_room!(name: "Move Source Room", capacity: 2)
    target = commit_room!(name: "Move Target Room", capacity: 2)
    date = future_date
    reservation = commit_reservation!(room: source, **slot(date, 1))

    get edit_admin_reservation_path(reservation)

    assert_response :success
    assert_select "form[action=?][method=?]", admin_reservation_path(reservation), "post" do
      assert_select "input[name=?][value=?]", "_method", "patch"
      assert_select "select[name=?] option[selected][value=?]",
        "reservation[room_id]", source.id.to_s
      assert_select "input[name=?][value=?]", "reservation[date]", date.iso8601
      assert_select "select[name=?] option[selected][value=?]", "reservation[start_hour]", "1"
      assert_select "input[type=?][value=?]", "submit", "Update reservation"
    end

    patch admin_reservation_path(reservation), params: {
      reservation: { room_id: target.id, date: date.iso8601, start_hour: 2 }
    }

    assert_response :see_other
    assert_equal admin_reservation_path(reservation), URI.parse(response.location).path
    reservation.reload
    assert_equal target.id, reservation.room_id
    assert_equal BookingSlots.interval(date, 2).first, reservation.start_datetime.utc
    assert_equal 0, occupancy(source, date, 1)
    assert_equal 1, occupancy(target, date, 2)

    follow_redirect!

    assert_response :success
    assert_includes response.body, "Reservation was successfully updated."
  end

  test "accepts an unchanged edit at capacity because the reservation excludes itself" do
    room = commit_room!(name: "Self Exclusion Room", capacity: 1)
    date = future_date
    reservation = commit_reservation!(room: room, **slot(date, 1))

    patch admin_reservation_path(reservation), params: {
      reservation: { room_id: room.id, date: date.iso8601, start_hour: 1 }
    }

    assert_response :see_other
    reservation.reload
    assert_equal BookingSlots.interval(date, 1).first, reservation.start_datetime.utc
    assert_equal 1, Reservation.where(room_id: room.id).count
    assert_equal 1, occupancy(room, date, 1)
  end

  test "refuses a full slot and shares the refusal with the public API" do
    room = commit_room!(name: "Shared Full Slot Room", capacity: 1)
    date = future_date
    commit_reservation!(room: room, **slot(date, 1))
    before = Reservation.where(room_id: room.id).count

    post admin_reservations_path, params: {
      reservation: { room_id: room.id, date: date.iso8601, start_hour: 1 }
    }

    assert_response :conflict
    assert_select ".admin-error", text: "This slot has just filled up. Select another time."
    assert_select "select[name=?] option[selected][value=?]", "reservation[room_id]", room.id.to_s
    assert_select "input[name=?][value=?]", "reservation[date]", date.iso8601
    assert_select "select[name=?] option[selected][value=?]", "reservation[start_hour]", "1"
    assert_equal before, Reservation.where(room_id: room.id).count

    post api_reservations_path,
      params: { reservation: { room_id: room.id, date: date.iso8601, start_hour: 1 } }.to_json,
      headers: { "CONTENT_TYPE" => "application/json", "ACCEPT" => "application/json" }

    assert_response :conflict
    assert_equal "slot_full", response.parsed_body.dig("error", "code")
    assert_equal before, Reservation.where(room_id: room.id).count
  end

  test "retains both original rows after an update slot refusal" do
    room = commit_room!(name: "Update Full Slot Room", capacity: 1)
    date = future_date
    first = commit_reservation!(room: room, **slot(date, 1))
    moving = commit_reservation!(room: room, **slot(date, 2))

    patch admin_reservation_path(moving), params: {
      reservation: { room_id: room.id, date: date.iso8601, start_hour: 1 }
    }

    assert_response :conflict
    assert_select ".admin-error", text: "This slot has just filled up. Select another time."
    assert_select "select[name=?] option[selected][value=?]", "reservation[start_hour]", "1"

    first.reload
    moving.reload
    assert_equal BookingSlots.interval(date, 1).first, first.start_datetime.utc
    assert_equal BookingSlots.interval(date, 2).first, moving.start_datetime.utc
    assert_equal 2, Reservation.where(room_id: room.id).count
  end

  test "rejects invalid input, preserves the submission and writes nothing" do
    room = commit_room!(name: "Invalid Reservation Room", capacity: 2)
    date = future_date
    before = Reservation.count

    post admin_reservations_path, params: {
      reservation: { room_id: room.id, date: date.iso8601, start_hour: 7 }
    }

    assert_response :unprocessable_entity
    assert_select ".admin-error", text: "Select a valid room, date and hour."
    assert_select "select[name=?] option[selected][value=?]", "reservation[room_id]", room.id.to_s
    assert_select "input[name=?][value=?]", "reservation[date]", date.iso8601
    assert_select "select[name=?] option[selected][value=?]", "reservation[start_hour]", "7"
    assert_select "select[name=?] option[value=?]", "reservation[start_hour]", "7",
      text: "Unsupported: 7"
    assert_equal before, Reservation.count

    post admin_reservations_path, params: {
      reservation: { room_id: [ room.id ], date: { year: "2026" }, start_hour: "1" }
    }

    assert_response :unprocessable_entity
    assert_select ".admin-error", text: "Select a valid room, date and hour."
    assert_equal before, Reservation.count
  end

  test "rejects a missing wrapper or blank submission with 422 and form defaults" do
    commit_room!(name: "Blank Submission Room", capacity: 2)
    before = Reservation.count

    post admin_reservations_path, params: {}

    assert_response :unprocessable_entity
    assert_select ".admin-error", text: "Select a valid room, date and hour."
    assert_select "input[name=?][value=?]", "reservation[date]", "2026-11-23"
    assert_equal before, Reservation.count

    post admin_reservations_path, params: {
      reservation: { room_id: "", date: "", start_hour: "" }
    }

    assert_response :unprocessable_entity
    assert_select ".admin-error", text: "Select a valid room, date and hour."
    assert_select "input[name=?][value=?]", "reservation[date]", "2026-11-23"
    assert_select "select[name=?] option[selected]", "reservation[room_id]", count: 0
    assert_select "select[name=?] option[selected]", "reservation[start_hour]", count: 0
    assert_equal before, Reservation.count
  end

  test "returns 404 for a missing room on create and a missing reservation on member routes" do
    date = future_date
    room = commit_room!(name: "Missing Reservation Room", capacity: 2)
    before = Reservation.count

    post admin_reservations_path, params: {
      reservation: { room_id: 999_999, date: date.iso8601, start_hour: 1 }
    }

    assert_response :not_found
    assert_select ".admin-error", text: "Room not found."
    assert_select "select[name=?] option[value=?]", "reservation[room_id]", "999999",
      text: "Unsupported: 999999"
    assert_equal before, Reservation.count

    reservation = commit_reservation!(room: room, **slot(date, 1))

    get edit_admin_reservation_path(999_999)
    assert_response :not_found

    patch admin_reservation_path(999_999), params: {
      reservation: { room_id: room.id, date: date.iso8601, start_hour: 2 }
    }
    assert_response :not_found

    delete admin_reservation_path(999_999)
    assert_response :not_found

    reservation.reload
    assert_equal BookingSlots.interval(date, 1).first, reservation.start_datetime.utc
  end

  test "deletes a future reservation" do
    room = commit_room!(name: "Delete Admin Reservation Room", capacity: 2)
    date = future_date
    reservation = commit_reservation!(room: room, **slot(date, 1))

    delete admin_reservation_path(reservation)

    assert_response :see_other
    assert_equal admin_reservations_path, URI.parse(response.location).path
    refute Reservation.exists?(reservation.id)

    follow_redirect!

    assert_response :success
    assert_includes response.body, "Reservation was successfully deleted."
  end

  test "redirects an edit of a started reservation, refuses its update and still deletes it" do
    room = nil
    reservation = nil
    historical_date = Date.new(2026, 11, 23)

    travel_to Time.utc(2026, 11, 22, 12, 0, 0) do
      room = commit_room!(name: "Historical Admin Reservation Room", capacity: 2)
      reservation = commit_reservation!(room: room, **slot(historical_date, 1))
    end

    get admin_reservation_path(reservation)

    assert_response :success
    assert_select "a[href=?]", edit_admin_reservation_path(reservation), count: 0
    assert_select "form[action=?] input[name=?][value=?]",
      admin_reservation_path(reservation), "_method", "delete"

    get edit_admin_reservation_path(reservation)

    assert_response :see_other
    assert_equal admin_reservation_path(reservation), URI.parse(response.location).path

    follow_redirect!

    assert_response :success
    assert_select ".admin-error", text: "Started reservations cannot be edited."

    patch admin_reservation_path(reservation), params: {
      reservation: { room_id: room.id, date: future_date.iso8601, start_hour: 2 }
    }

    assert_response :unprocessable_entity
    assert_select ".admin-error", text: "Select a slot that has not started."
    reservation.reload
    assert_equal BookingSlots.interval(historical_date, 1).first, reservation.start_datetime.utc

    delete admin_reservation_path(reservation)

    assert_response :see_other
    assert_equal admin_reservations_path, URI.parse(response.location).path
    refute Reservation.exists?(reservation.id)
  end

  test "returns 404 for malformed member ids without touching an aliased record" do
    room = commit_room!(name: "Malformed Id Room", capacity: 2)
    date = future_date
    reservation = commit_reservation!(room: room, **slot(date, 1))

    malformed_ids = [ "#{reservation.id}abc", "#{reservation.id}e0", "9223372036854775808" ]

    malformed_ids.each do |id|
      get admin_reservation_path(id)
      assert_response :not_found, "expected GET #{id.inspect} to be 404"

      patch admin_reservation_path(id), params: {
        reservation: { room_id: room.id, date: date.iso8601, start_hour: 2 }
      }
      assert_response :not_found, "expected PATCH #{id.inspect} to be 404"

      delete admin_reservation_path(id)
      assert_response :not_found, "expected DELETE #{id.inspect} to be 404"
    end

    reservation.reload
    assert_equal BookingSlots.interval(date, 1).first, reservation.start_datetime.utc
    assert Reservation.exists?(reservation.id)
  end

  test "an expired session cannot create, update or delete reservations" do
    room = commit_room!(name: "Expired Session Room", capacity: 2)
    date = future_date
    reservation = commit_reservation!(room: room, **slot(date, 2))

    travel 8.hours + 1.second do
      post admin_reservations_path, params: {
        reservation: { room_id: room.id, date: date.iso8601, start_hour: 1 }
      }
      assert_response :forbidden

      patch admin_reservation_path(reservation), params: {
        reservation: { room_id: room.id, date: date.iso8601, start_hour: 3 }
      }
      assert_response :forbidden

      delete admin_reservation_path(reservation)
      assert_response :forbidden
    end

    assert_equal 1, Reservation.where(room_id: room.id).count
    assert_equal 2, reservation.reload.start_datetime.utc.hour
  end

  test "rejects anonymous form and write routes before lookup" do
    room = commit_room!(name: "Anonymous Write Room", capacity: 2)
    date = future_date
    reservation = commit_reservation!(room: room, **slot(date, 1))
    before = Reservation.where(room_id: room.id).count

    open_session do |guest|
      guest.get new_admin_reservation_path
      assert_equal 403, guest.response.status

      guest.post admin_reservations_path, params: {
        reservation: { room_id: room.id, date: date.iso8601, start_hour: 2 }
      }
      assert_equal 403, guest.response.status

      guest.get edit_admin_reservation_path(reservation)
      assert_equal 403, guest.response.status

      guest.patch admin_reservation_path(reservation), params: {
        reservation: { room_id: room.id, date: date.iso8601, start_hour: 2 }
      }
      assert_equal 403, guest.response.status

      guest.delete admin_reservation_path(reservation)
      assert_equal 403, guest.response.status
    end

    assert_equal before, Reservation.where(room_id: room.id).count
    assert Reservation.exists?(reservation.id)
  end

  test "returns 503 and keeps rows when create, update or delete is busy" do
    room = commit_room!(name: "Busy Admin Reservation Room", capacity: 2)
    date = future_date
    reservation = commit_reservation!(room: room, **slot(date, 2))
    create = Reservations::Create.singleton_class
    create.alias_method :__admin_create, :call
    Reservations::Create.define_singleton_method(:call) { |**| BusyFailure.new }
    update = Reservations::Update.singleton_class
    update.alias_method :__admin_update, :call
    Reservations::Update.define_singleton_method(:call) { |**| BusyFailure.new }
    destroy = Reservations::Destroy.singleton_class
    destroy.alias_method :__admin_destroy, :call
    Reservations::Destroy.define_singleton_method(:call) { |**| BusyFailure.new }

    begin
      post admin_reservations_path, params: {
        reservation: { room_id: room.id, date: date.iso8601, start_hour: 1 }
      }

      assert_response :service_unavailable
      assert_select ".admin-error", text: "The booking system is busy. Try again."
      assert_equal 1, Reservation.where(room_id: room.id).count

      patch admin_reservation_path(reservation), params: {
        reservation: { room_id: room.id, date: date.iso8601, start_hour: 1 }
      }

      assert_response :service_unavailable
      assert_select ".admin-error", text: "The booking system is busy. Try again."
      assert_select "h2", text: "Edit reservation ##{reservation.id}"
      assert_select "select[name=?] option[selected][value=?]", "reservation[start_hour]", "1"
      assert_equal 2, reservation.reload.start_datetime.utc.hour

      delete admin_reservation_path(reservation)

      assert_response :service_unavailable
      assert_select ".admin-error", text: "The booking system is busy. Try again."
      assert_select "h2", text: "Reservation ##{reservation.id}"
      assert Reservation.exists?(reservation.id)
    ensure
      create.alias_method :call, :__admin_create
      create.remove_method :__admin_create
      update.alias_method :call, :__admin_update
      update.remove_method :__admin_update
      destroy.alias_method :call, :__admin_destroy
      destroy.remove_method :__admin_destroy
    end
  end

  test "rejects a reservation POST without a CSRF token when forgery protection is enabled" do
    room = commit_room!(name: "CSRF Admin Reservation Room", capacity: 2)
    before = Reservation.where(room_id: room.id).count
    previous = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true

    begin
      post admin_reservations_path, params: {
        reservation: { room_id: room.id, date: future_date.iso8601, start_hour: 1 }
      }

      assert_response :unprocessable_entity
      assert_equal before, Reservation.where(room_id: room.id).count
    ensure
      ActionController::Base.allow_forgery_protection = previous
    end
  end

  private

  def sign_in_admin
    post admin_session_path, params: {
      session: { email_address: ADMIN_EMAIL, password: PASSWORD }
    }
    assert_response :see_other
  end

  def slot(date, hour)
    start_at, end_at = BookingSlots.interval(date, hour)

    { start_at: start_at, end_at: end_at }
  end

  def occupancy(room, date, hour)
    start_at, = BookingSlots.interval(date, hour)
    Reservation.where(room_id: room.id, start_datetime: start_at).count
  end

  def future_date
    Time.current.to_date + 1
  end
end
