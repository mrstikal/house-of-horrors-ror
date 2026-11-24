require "test_helper"
require_relative "../support/committed_test_data"

class PublicBookingApiTest < ActionDispatch::IntegrationTest
  include CommittedTestData

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
  end

  teardown do
    travel_back if @time_frozen
  end

  test "returns availability with aggregate slots and no individual bookings" do
    room = commit_room!(capacity: 2, name: "API Availability Room")
    book(room, 1)

    get api_availability_path, params: { room_id: room.id, date: future_date.iso8601 }

    assert_response :success
    assert_equal "application/json", response.media_type
    assert_equal "no-store", response.headers["Cache-Control"]

    body = response.parsed_body
    assert_equal room.id, body["room_id"]
    assert_equal future_date.iso8601, body["date"]
    assert_equal (1..6).to_a, body["slots"].map { |slot| slot["start_hour"] }

    first = body["slots"].first
    assert_equal [ "end_datetime", "label", "nearly_full", "remaining", "start_datetime", "start_hour" ],
      first.keys.sort
    assert_equal BookingSlots.interval(future_date, 1).first.iso8601, first["start_datetime"]
    assert_equal BookingSlots.interval(future_date, 1).last.iso8601, first["end_datetime"]
    assert_equal "01:00-02:00 UTC", first["label"]
    assert_equal 1, first["remaining"]
    assert first["nearly_full"]
    assert_equal 2, body["slots"].second["remaining"]
    refute body["slots"].second["nearly_full"]
    refute body.key?("reservations")
    assert body["slots"].none? { |slot| slot.key?("id") || slot.key?("reservation_id") }
  end

  test "keeps an empty one-person bathroom not nearly full" do
    room = commit_room!(capacity: 1, name: "API Bathroom Room")

    get api_availability_path, params: { room_id: room.id, date: future_date.iso8601 }

    assert_response :success
    slot = response.parsed_body["slots"].first
    assert_equal 1, slot["remaining"]
    refute slot["nearly_full"]
  end

  test "marks a near-full slot and omits a full slot" do
    near_full = commit_room!(capacity: 2, name: "API Near Full Room")
    full = commit_room!(capacity: 1, name: "API Full Room")
    book(near_full, 1)
    book(full, 1)

    get api_availability_path, params: { room_id: near_full.id, date: future_date.iso8601 }
    assert_response :success
    assert_equal 1, response.parsed_body["slots"].first["remaining"]
    assert response.parsed_body["slots"].first["nearly_full"]

    get api_availability_path, params: { room_id: full.id, date: future_date.iso8601 }
    assert_response :success
    assert_equal (2..6).to_a, response.parsed_body["slots"].map { |slot| slot["start_hour"] }
  end

  test "returns an empty slot list when every hour is full" do
    room = commit_room!(capacity: 1, name: "API Full Day Room")

    BookingSlots::HOURS.each { |hour| book(room, hour) }

    get api_availability_path, params: { room_id: room.id, date: future_date.iso8601 }

    assert_response :success
    assert_equal [], response.parsed_body["slots"]
  end

  test "suppresses started slots on the same day" do
    room = commit_room!(capacity: 2, name: "API Same Day Room")

    travel_to Time.utc(2026, 11, 23, 1, 30, 0) do
      get api_availability_path, params: { room_id: room.id, date: "2026-11-23" }

      assert_response :success
      assert_equal (2..6).to_a, response.parsed_body["slots"].map { |slot| slot["start_hour"] }
    end
  end

  test "returns 404 and 422 envelopes for bad availability input" do
    room = commit_room!(capacity: 2, name: "API Bad Availability Room")

    get api_availability_path, params: { room_id: 999_999, date: future_date.iso8601 }
    assert_response :not_found
    assert_equal "not_found", response.parsed_body.dig("error", "code")

    get api_availability_path, params: { room_id: "abc", date: future_date.iso8601 }
    assert_response :unprocessable_entity
    assert_equal "invalid_input", response.parsed_body.dig("error", "code")

    get api_availability_path, params: { room_id: room.id, date: "not-a-date" }
    assert_response :unprocessable_entity
    assert_equal "invalid_input", response.parsed_body.dig("error", "code")

    get api_availability_path, params: { room_id: room.id, date: (future_date - 2).iso8601 }
    assert_response :unprocessable_entity
    assert_equal "invalid_input", response.parsed_body.dig("error", "code")
  end

  test "creates a reservation and returns stored UTC datetimes" do
    room = commit_room!(capacity: 2, name: "API Create Room")

    post_json(reservation_payload(room, 1))

    assert_response :created
    assert_equal "application/json", response.media_type
    body = response.parsed_body
    start_at, end_at = BookingSlots.interval(future_date, 1)

    assert_equal room.id, body.dig("reservation", "room_id")
    assert_equal start_at.iso8601, body.dig("reservation", "start_datetime")
    assert_equal end_at.iso8601, body.dig("reservation", "end_datetime")
    record = Reservation.find(body.dig("reservation", "id"))
    assert_equal start_at, record.start_datetime.utc
    assert_equal end_at, record.end_datetime.utc
    assert_equal 1, Reservation.where(room_id: room.id).count
  end

  test "returns 422 for a missing or non-object reservation wrapper" do
    room = commit_room!(capacity: 2, name: "API Wrapper Room")

    post_json({})
    assert_response :unprocessable_entity
    assert_equal "invalid_input", response.parsed_body.dig("error", "code")

    post_json({ reservation: "nope" })
    assert_response :unprocessable_entity
    assert_equal "invalid_input", response.parsed_body.dig("error", "code")

    post_json({ reservation: { room_id: room.id, date: "not-a-date", start_hour: 1 } })
    assert_response :unprocessable_entity
    assert_equal "invalid_input", response.parsed_body.dig("error", "code")

    post_json({ reservation: { room_id: room.id, date: future_date.iso8601, start_hour: 7 } })
    assert_response :unprocessable_entity
    assert_equal "invalid_input", response.parsed_body.dig("error", "code")
    assert_equal 0, Reservation.where(room_id: room.id).count
  end

  test "returns a framework 400 for malformed JSON and writes nothing" do
    room = commit_room!(capacity: 2, name: "API Malformed Room")

    post api_reservations_path, params: '{"reservation":'.dup,
      headers: { "CONTENT_TYPE" => "application/json", "ACCEPT" => "application/json" }

    assert_response :bad_request
    assert_empty response.body
    assert_equal 0, Reservation.where(room_id: room.id).count
  end

  test "returns 404 for a missing room on create" do
    post_json({ reservation: { room_id: 999_999, date: future_date.iso8601, start_hour: 1 } })

    assert_response :not_found
    assert_equal "not_found", response.parsed_body.dig("error", "code")
  end

  test "returns 409 for a full slot and keeps the row count" do
    room = commit_room!(capacity: 1, name: "API Slot Full Room")
    book(room, 1)

    post_json(reservation_payload(room, 1))

    assert_response :conflict
    assert_equal "slot_full", response.parsed_body.dig("error", "code")
    assert_includes response.parsed_body.dig("error", "messages"), "This slot has just filled up. Select another time."
    assert_equal 1, Reservation.where(room_id: room.id).count
  end

  test "cannot overbook after a stale availability read" do
    room = commit_room!(capacity: 1, name: "API Stale Room")

    get api_availability_path, params: { room_id: room.id, date: future_date.iso8601 }
    assert_response :success
    assert_equal 1, response.parsed_body["slots"].first["remaining"]

    post_json(reservation_payload(room, 1))
    assert_response :created

    post_json(reservation_payload(room, 1))
    assert_response :conflict
    assert_equal "slot_full", response.parsed_body.dig("error", "code")
    assert_equal 1, Reservation.where(room_id: room.id).count
  end

  test "returns 503 for a busy operation without writing" do
    room = commit_room!(capacity: 2, name: "API Busy Room")
    before = Reservation.where(room_id: room.id).count

    create = Reservations::Create.singleton_class
    create.alias_method :__api_with_lock, :call
    Reservations::Create.define_singleton_method(:call) { |**| BusyFailure.new }

    begin
      post_json(reservation_payload(room, 1))
    ensure
      create.alias_method :call, :__api_with_lock
      create.remove_method :__api_with_lock
    end

    assert_response :service_unavailable
    assert_equal "busy", response.parsed_body.dig("error", "code")
    assert_equal before, Reservation.where(room_id: room.id).count
  end

  test "rejects a POST without a CSRF token when forgery protection is enabled" do
    previous = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true

    begin
      get root_path
      assert_response :success
      token = css_select("meta[name='csrf-token']").first&.[]("content")
      assert token.present?

      room = commit_room!(capacity: 2, name: "API CSRF Room")
      post_json(reservation_payload(room, 1), headers: { "X-CSRF-Token" => token })
      assert_response :created

      before = Reservation.where(room_id: room.id).count
      post_json(reservation_payload(room, 2))
      assert_response :unprocessable_entity
      assert_equal before, Reservation.where(room_id: room.id).count
    ensure
      ActionController::Base.allow_forgery_protection = previous
    end
  end

  private

  def post_json(payload, headers: {})
    post api_reservations_path,
      params: payload.to_json,
      headers: {
        "CONTENT_TYPE" => "application/json",
        "ACCEPT" => "application/json"
      }.merge(headers)
  end

  def reservation_payload(room, hour)
    {
      reservation: {
        room_id: room.id,
        date: future_date.iso8601,
        start_hour: hour
      }
    }
  end

  def book(room, hour)
    start_at, end_at = BookingSlots.interval(future_date, hour)
    commit_reservation!(room: room, start_at: start_at, end_at: end_at)
  end

  def future_date
    Time.current.to_date + 1
  end
end
