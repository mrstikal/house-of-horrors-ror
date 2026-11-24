require "test_helper"
require_relative "../support/committed_test_data"
require_relative "../support/admin_session_test_helper"

class AdminRoomsTest < ActionDispatch::IntegrationTest
  include CommittedTestData
  include AdminSessionTestHelper

  ADMIN_EMAIL = "rooms-admin@example.test"
  PASSWORD = "admin rooms password"

  setup do
    @created_room_ids = []
    @admin = User.create!(email_address: ADMIN_EMAIL, password: PASSWORD, role: "admin")
    sign_in_admin
  end

  teardown do
    room_ids = @created_room_ids || []
    Reservation.where(room_id: room_ids).delete_all if room_ids.any?
    Room.where(id: room_ids).delete_all if room_ids.any?
    User.where(email_address: ADMIN_EMAIL).delete_all
  end

  test "renders the workspace list, details, new form and edit form" do
    room = commit_room!(
      name: "Visible Admin Room",
      description: "Visible admin description.",
      capacity: 3,
      image_key: "attic"
    )
    start_at, end_at = BookingSlots.interval(future_date, 1)
    commit_reservation!(room: room, start_at: start_at, end_at: end_at)

    get admin_rooms_path
    assert_response :success
    assert_select "html[lang='en']", count: 1
    assert_select "head", count: 1
    assert_select "meta[charset='utf-8']"
    assert_select "nav[aria-label='Primary'] a", text: "Homepage"
    assert_select "nav[aria-label='Primary'] a", text: "Admin"
    assert_select "nav[aria-label='Administration'] a[aria-current='page']", text: "Rooms"
    assert_select "form[action=?] button", admin_session_path, text: "Log out"
    assert_select ".admin-rooms-list a", text: "Visible Admin Room"

    get admin_room_path(room)
    assert_response :success
    assert_select "h2", text: "Visible Admin Room"
    assert_select "img[src=?]", ApplicationController.helpers.room_image_url(room)
    assert_includes response.body, "Visible admin description."
    assert_select ".admin-room-facts dd", text: "3"
    assert_select ".admin-room-facts dd", text: "1"
    assert_select "[aria-current='page']", count: 1
    assert_select ".admin-room-actions form[action=?]", admin_room_path(room)
    assert_select "a[href=?]", admin_reservations_path(room_id: room.id), text: "View bookings"

    get new_admin_room_path
    assert_response :success
    assert_select "form[action=?][method=?]", admin_rooms_path, "post"
    assert_select "select[name=?]", "room[image_choice]" do
      RoomImages.keys.each do |key|
        assert_select "option[value=?]", "bundled:#{key}"
      end
    end

    get edit_admin_room_path(room)
    assert_response :success
    assert_select "form[action=?][method=?]", admin_room_path(room), "post"
    assert_select "input[name=?][value=?]", "room[name]", "Visible Admin Room"
    assert_select "select[name=?] option[selected][value=?]", "room[image_choice]", "bundled:attic"
  end

  test "orders the room list by name then id" do
    commit_room!(name: "Zulu Admin Room")
    commit_room!(name: "Alpha Admin Room")

    get admin_rooms_path

    assert_response :success
    names = css_select(".admin-rooms-list ul a").map(&:text)
    assert_operator names.index("Alpha Admin Room"), :<, names.index("Zulu Admin Room")
  end

  test "creates a room and ignores extra submitted fields" do
    post admin_rooms_path, params: {
      room: {
        name: "Created Admin Room",
        description: "Created through the form.",
        capacity: 2,
        image_choice: "bundled:kitchen",
        image_key: "attic",
        seed_key: "ignored-seed"
      }
    }

    room = Room.find_by!(name: "Created Admin Room")
    assert_response :see_other
    assert_equal admin_room_path(room), URI.parse(response.location).path
    @created_room_ids << room.id

    follow_redirect!
    assert_response :success
    assert_includes response.body, "Room was successfully created."
    assert_equal "Created through the form.", room.description
    assert_equal 2, room.capacity
    assert_equal "kitchen", room.image_key
    assert_nil room.image_blob_id
    assert_nil room.seed_key
  end

  test "updates a room" do
    room = commit_room!(name: "Editable Admin Room", capacity: 2, image_key: "basement")

    patch admin_room_path(room), params: {
      room: {
        name: "Updated Admin Room",
        description: "Updated through the form.",
        capacity: 3,
        image_choice: "bundled:attic"
      }
    }

    assert_response :see_other
    assert_equal admin_room_path(room), URI.parse(response.location).path

    follow_redirect!
    assert_response :success
    assert_includes response.body, "Room was successfully updated."
    room.reload
    assert_equal "Updated Admin Room", room.name
    assert_equal "Updated through the form.", room.description
    assert_equal 3, room.capacity
    assert_equal "attic", room.image_key
    assert_nil room.image_blob_id
  end

  test "deletes an empty room" do
    room = commit_room!(name: "Deletable Admin Room")

    delete admin_room_path(room)

    assert_response :see_other
    assert_equal admin_rooms_path, URI.parse(response.location).path
    refute Room.exists?(room.id)

    follow_redirect!
    assert_response :success
    assert_includes response.body, "Room was successfully deleted."
  end

  test "rejects invalid create and preserves submitted values" do
    before = Room.count

    post admin_rooms_path, params: {
      room: {
        name: "Invalid Submitted Room",
        description: "Submitted description.",
        capacity: 0,
        image_choice: "bundled:basement"
      }
    }

    assert_response :unprocessable_entity
    assert_equal before, Room.count
    assert_includes response.body, "Capacity must be greater than or equal to 1"
    assert_select "input[name=?][value=?]", "room[name]", "Invalid Submitted Room"
    assert_select "input[name=?][value=?]", "room[capacity]", "0"
    assert_select "select[name=?] option[selected][value=?]", "room[image_choice]", "bundled:basement"
    assert_select "form[action=?]", admin_rooms_path
  end

  test "returns 422 for scalar and array room wrappers" do
    room = commit_room!(name: "Malformed Wrapper Room", capacity: 2)

    [ "not-a-room", [ "name" ] ].each do |wrapper|
      post admin_rooms_path, params: { room: wrapper }
      assert_response :unprocessable_entity
      assert_select ".admin-error", text: "Select valid room details."

      patch admin_room_path(room), params: { room: wrapper }
      assert_response :unprocessable_entity
      assert_select ".admin-error", text: "Select valid room details."
    end

    post admin_rooms_path
    assert_response :unprocessable_entity
    assert_select ".admin-error", text: "Select valid room details."

    patch admin_room_path(room)
    assert_response :unprocessable_entity
    assert_select ".admin-error", text: "Select valid room details."

    assert_equal "Malformed Wrapper Room", room.reload.name
  end

  test "preserves raw capacity and an unsupported image choice on refusal" do
    before = Room.count

    post admin_rooms_path, params: {
      room: {
        name: "Raw Values Admin Room",
        description: "Raw values description.",
        capacity: "abc",
        image_choice: "not-a-choice"
      }
    }

    assert_response :unprocessable_entity
    assert_equal before, Room.count
    assert_select "input[name=?][value=?]", "room[capacity]", "abc"
    assert_select "select[name=?] option[selected][value=?]", "room[image_choice]", "not-a-choice"
  end

  test "rejects malformed and unknown image choices without changing the stored reference" do
    room = commit_room!(name: "Choice Admin Room", image_key: "basement")

    [ "bundled:unknown", "upload:999999", "upload:abc", "nonsense", "", "upload:" ].each do |choice|
      patch admin_room_path(room), params: { room: { image_choice: choice } }

      assert_response :unprocessable_entity
      assert_select ".admin-error", text: "Select a valid room image."
    end

    room.reload
    assert_equal "basement", room.image_key
    assert_nil room.image_blob_id
  end

  test "rejects creating a room without an image choice" do
    before = Room.count

    post admin_rooms_path, params: {
      room: { name: "No Image Admin Room", description: "No image description.", capacity: 2 }
    }

    assert_response :unprocessable_entity
    assert_includes response.body, "Select exactly one room image."
    assert_equal before, Room.count
  end

  test "rejects capacity below the peak and preserves the database row" do
    room = commit_room!(name: "Reduction Admin Room", capacity: 2)
    start_at, end_at = BookingSlots.interval(future_date, 1)
    2.times { commit_reservation!(room: room, start_at: start_at, end_at: end_at) }

    patch admin_room_path(room), params: { room: { capacity: 1 } }

    assert_response :conflict
    assert_includes response.body, "Capacity cannot be lower than the existing peak of 2."
    assert_select "input[name=?][value=?]", "room[capacity]", "1"
    assert_equal 2, room.reload.capacity
    assert_equal "basement", room.image_key
    assert Room.exists?(room.id)
  end

  test "rejects deleting a room with reservations" do
    room = commit_room!(name: "Booked Admin Room", capacity: 2)
    start_at, end_at = BookingSlots.interval(future_date, 1)
    commit_reservation!(room: room, start_at: start_at, end_at: end_at)

    delete admin_room_path(room)

    assert_response :conflict
    assert_select ".admin-error", text: "Delete this room's reservations before deleting the room."
    assert Room.exists?(room.id)
    assert Reservation.exists?(room_id: room.id)
  end

  test "a public booking honors the capacity edited through admin" do
    room = commit_room!(name: "Capacity API Admin Room", capacity: 2)
    date = future_date

    patch admin_room_path(room), params: { room: { capacity: 1 } }
    assert_response :see_other

    post api_reservations_path,
      params: { reservation: { room_id: room.id, date: date.iso8601, start_hour: 1 } }.to_json,
      headers: { "CONTENT_TYPE" => "application/json", "ACCEPT" => "application/json" }
    assert_response :created

    post api_reservations_path,
      params: { reservation: { room_id: room.id, date: date.iso8601, start_hour: 1 } }.to_json,
      headers: { "CONTENT_TYPE" => "application/json", "ACCEPT" => "application/json" }
    assert_response :conflict
    assert_equal "slot_full", response.parsed_body.dig("error", "code")
    assert_equal 1, Reservation.where(room_id: room.id).count
  end

  test "rejects anonymous access to all seven room routes before lookup" do
    open_session do |guest|
      guest.get admin_rooms_path
      assert_equal 403, guest.response.status

      guest.get admin_room_path(999_999)
      assert_equal 403, guest.response.status

      guest.get new_admin_room_path
      assert_equal 403, guest.response.status

      guest.post admin_rooms_path, params: { room: { name: "Anonymous" } }
      assert_equal 403, guest.response.status

      guest.get edit_admin_room_path(999_999)
      assert_equal 403, guest.response.status

      guest.patch admin_room_path(999_999), params: { room: { name: "Anonymous" } }
      assert_equal 403, guest.response.status

      guest.delete admin_room_path(999_999)
      assert_equal 403, guest.response.status
    end
  end

  test "returns 404 for malformed room ids without touching an aliased room" do
    room = commit_room!(name: "Malformed Room Id", capacity: 2)

    [ "#{room.id}abc", "#{room.id}e0", "9223372036854775808" ].each do |id|
      get admin_room_path(id)
      assert_response :not_found

      get edit_admin_room_path(id)
      assert_response :not_found

      patch admin_room_path(id), params: { room: { name: "Aliased Room" } }
      assert_response :not_found

      delete admin_room_path(id)
      assert_response :not_found
    end

    room.reload
    assert_equal "Malformed Room Id", room.name
    assert_equal "basement", room.image_key
    assert Room.exists?(room.id)
  end

  test "returns 404 for an authorized missing room on every member route" do
    get admin_room_path(999_999)
    assert_response :not_found

    get edit_admin_room_path(999_999)
    assert_response :not_found

    patch admin_room_path(999_999), params: { room: { name: "Missing" } }
    assert_response :not_found

    delete admin_room_path(999_999)
    assert_response :not_found
  end

  private

  def sign_in_admin
    post admin_session_path, params: {
      session: { email_address: ADMIN_EMAIL, password: PASSWORD }
    }
    assert_response :see_other
  end

  def future_date
    Time.current.to_date + 1
  end
end
