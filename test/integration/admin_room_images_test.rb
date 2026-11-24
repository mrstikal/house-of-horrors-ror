require "test_helper"
require "tempfile"
require_relative "../support/committed_test_data"
require_relative "../support/admin_session_test_helper"

class AdminRoomImagesTest < ActionDispatch::IntegrationTest
  include CommittedTestData
  include AdminSessionTestHelper

  ADMIN_EMAIL = "images-admin@example.test"
  PASSWORD = "admin images password"

  setup do
    @created_room_ids = []
    @uploaded_blobs = []
    @tempfiles = []
    @admin = User.create!(email_address: ADMIN_EMAIL, password: PASSWORD, role: "admin")
    sign_in_admin
  end

  teardown do
    room_ids = ((@committed_room_ids || []) + (@created_room_ids || [])).uniq
    Reservation.where(room_id: room_ids).delete_all if room_ids.any?
    Room.where(id: room_ids).delete_all if room_ids.any?
    (@uploaded_blobs || []).each do |blob|
      ActiveStorage::Blob.where(id: blob.id).delete_all
      blob.service.delete(blob.key)
    rescue ActiveStorage::FileNotFoundError
      nil
    end
    (@tempfiles || []).each do |tempfile|
      tempfile.close
      tempfile.unlink
    rescue IOError, SystemCallError
      nil
    end
    User.where(email_address: ADMIN_EMAIL).delete_all
  end

  test "renders the multipart upload form only on the rooms index" do
    get admin_rooms_path

    assert_response :success
    assert_select "form[action=?][method=?][enctype=?]", admin_room_images_path, "post", "multipart/form-data" do
      assert_select "input[type=?][name=?][accept=?][required]", "file", "image", "image/png,image/jpeg"
      assert_select "input[type=?][value=?]", "submit", "Upload image"
    end
    assert_select "form.admin-room-form", count: 0

    room = commit_room!(name: "Upload Form Room")

    get admin_room_path(room)
    assert_response :success
    assert_select "form[action=?]", admin_room_images_path, count: 0

    get new_admin_room_path
    assert_response :success
    assert_select "form[action=?]", admin_room_images_path, count: 0
    assert_select "select[name=?]", "room[image_choice]"
  end

  test "uploads a PNG and redirects with the generated catalog filename" do
    before_rooms = Room.count
    before_ids = RoomImages.uploads.pluck(:id)

    post admin_room_images_path, params: { image: upload_param(bytes: png_fixture_bytes) }

    assert_response :see_other
    assert_equal admin_rooms_path, URI.parse(response.location).path
    assert_equal before_rooms, Room.count

    blob = RoomImages.uploads.where.not(id: before_ids).order(:id).first
    assert blob, "expected one new catalog blob"
    track_blob(blob)
    assert_equal "image/png", blob.content_type
    assert_match(/\Aroom-[0-9a-f-]{36}\.png\z/, blob.filename.to_s)

    follow_redirect!
    assert_response :success
    assert_select ".admin-notice" do |elements|
      assert_includes elements.first.text, blob.filename.to_s
    end

    get new_admin_room_path
    assert_response :success
    assert_select "select[name=?] option[value=?]", "room[image_choice]", "upload:#{blob.id}",
      text: blob.filename.to_s
  end

  test "rejects spoofed MIME, SVG and oversized uploads without catalog rows or room changes" do
    room = commit_room!(name: "Untouched Upload Room", image_key: "basement")
    before_ids = RoomImages.uploads.pluck(:id)
    before_rooms = Room.count
    svg = %q(<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"><rect width="10" height="10"/></svg>)

    uploads = [
      upload_param(bytes: svg, filename: "room.png", content_type: "image/png"),
      upload_param(bytes: svg, filename: "room.svg", content_type: "image/svg+xml"),
      upload_param(bytes: "x" * (2.megabytes + 1), filename: "big.png", content_type: "image/png")
    ]

    uploads.each do |upload|
      post admin_room_images_path, params: { image: upload }

      assert_response :unprocessable_entity
      assert_select ".admin-error", text: "Upload a PNG or JPEG of at most 2 MiB."
      assert_select "h2", text: "Manage rooms"
      assert_equal before_ids.sort, RoomImages.uploads.pluck(:id).sort
      assert_equal before_rooms, Room.count
    end

    room.reload
    assert_equal "basement", room.image_key
    assert_nil room.image_blob_id
  end

  test "returns 503 without a catalog row when disk storage fails" do
    before_ids = RoomImages.uploads.pluck(:id)
    service_class = ActiveStorage::Blob.service.class
    assert_equal "ActiveStorage::Service::DiskService", service_class.name
    service_class.alias_method :__test_upload, :upload
    service_class.define_method(:upload) { |*_args, **_kwargs| raise IOError, "disk unavailable" }

    begin
      post admin_room_images_path, params: { image: upload_param(bytes: png_fixture_bytes) }
    ensure
      service_class.alias_method :upload, :__test_upload
      service_class.remove_method :__test_upload
    end

    assert_response :service_unavailable
    assert_select ".admin-error", text: "Could not store the image. Try again."
    assert_select "h2", text: "Manage rooms"
    assert_equal before_ids.sort, RoomImages.uploads.pluck(:id).sort
  end

  test "creates a room with an uploaded image and reuses it for a second room" do
    blob = upload_png_via_http

    first = create_room_with_choice!("First Uploaded Room", "upload:#{blob.id}")
    assert_nil first.image_key
    assert_equal blob.id, first.image_blob_id

    get edit_admin_room_path(first)
    assert_response :success
    assert_select "select[name=?] option[selected][value=?]", "room[image_choice]", "upload:#{blob.id}"

    second = create_room_with_choice!("Second Uploaded Room", "upload:#{blob.id}")
    assert_equal blob.id, second.image_blob_id

    get room_photo_path(blob)
    assert_response :success
    assert_equal png_fixture_bytes, response.body
    assert_equal "image/png", response.media_type

    get admin_room_path(first)
    assert_response :success
    assert_select "img[src=?]", room_photo_path(blob)
  end

  test "replaces the image for one room and keeps the old image for the other" do
    first_blob = upload_png_via_http
    second_blob = upload_png_via_http

    first = create_room_with_choice!("Replace First Room", "upload:#{first_blob.id}")
    second = create_room_with_choice!("Replace Second Room", "upload:#{first_blob.id}")

    patch admin_room_path(first), params: { room: { image_choice: "upload:#{second_blob.id}" } }

    assert_response :see_other
    assert_equal second_blob.id, first.reload.image_blob_id
    assert_equal first_blob.id, second.reload.image_blob_id

    get room_photo_path(first_blob)
    assert_response :success
    assert_equal png_fixture_bytes, response.body
    assert ActiveStorage::Blob.exists?(first_blob.id)
    assert first_blob.service.exist?(first_blob.key)

    get admin_room_path(first)
    assert_response :success
    assert_select "img[src=?]", room_photo_path(second_blob)
  end

  test "leaves bundled rooms unchanged when an image is uploaded" do
    room = commit_room!(name: "Bundled Upload Room", image_key: "attic")

    upload_png_via_http

    room.reload
    assert_equal "attic", room.image_key
    assert_nil room.image_blob_id
  end

  test "rejects anonymous uploads before any storage work" do
    before_ids = RoomImages.uploads.pluck(:id)
    upload = upload_param(bytes: png_fixture_bytes)

    open_session do |guest|
      guest.post admin_room_images_path, params: { image: upload }
      assert_equal 403, guest.response.status
    end

    assert_equal before_ids.sort, RoomImages.uploads.pluck(:id).sort
  end

  private

  def sign_in_admin
    post admin_session_path, params: {
      session: { email_address: ADMIN_EMAIL, password: PASSWORD }
    }
    assert_response :see_other
  end

  def upload_png_via_http
    before_ids = RoomImages.uploads.pluck(:id)

    post admin_room_images_path, params: { image: upload_param(bytes: png_fixture_bytes) }

    assert_response :see_other
    blob = RoomImages.uploads.where.not(id: before_ids).order(:id).first
    assert blob, "expected one new catalog blob"
    track_blob(blob)
    blob
  end

  def create_room_with_choice!(name, choice)
    post admin_rooms_path, params: {
      room: {
        name: name,
        description: "Created with an uploaded catalog image.",
        capacity: 2,
        image_choice: choice
      }
    }

    assert_response :see_other
    room = Room.find_by!(name: name)
    @created_room_ids << room.id
    room
  end

  def upload_param(bytes: nil, content_type: "image/png", filename: "room.png")
    tempfile = Tempfile.new([ "room-image-http", File.extname(filename) ])
    tempfile.binmode
    tempfile.write(bytes)
    tempfile.rewind
    @tempfiles << tempfile

    Rack::Test::UploadedFile.new(tempfile.path, content_type, true, original_filename: filename)
  end

  def png_fixture_bytes
    File.binread(Rails.root.join("test/fixtures/files/room.png"))
  end

  def track_blob(blob)
    @uploaded_blobs << blob
    blob
  end
end
