require "test_helper"
require "stringio"

class RoomPhotosTest < ActionDispatch::IntegrationTest
  setup do
    @uploaded_blobs = []
  end

  teardown do
    (@uploaded_blobs || []).each do |blob|
      blob.service.delete(blob.key)
    rescue ActiveStorage::FileNotFoundError
      nil
    end
  end

  test "serves linked uploaded PNG bytes with safe headers" do
    bytes = fixture_bytes
    blob = uploaded_blob(bytes: bytes, content_type: "image/png")
    create_uploaded_room(blob)

    get room_photo_path(blob)

    assert_response :success
    assert_equal "image/png", response.media_type
    assert_equal bytes, response.body
    assert_includes response.headers["Content-Disposition"], "inline"
    assert_equal "nosniff", response.headers["X-Content-Type-Options"]
  end

  test "serves linked uploaded JPEG bytes" do
    bytes = File.binread(Rails.root.join("app/assets/images/house_of_horrors/room1.jpg"))
    blob = uploaded_blob(bytes: bytes, content_type: "image/jpeg", filename: "room.jpg")
    create_uploaded_room(blob)

    get room_photo_path(blob)

    assert_response :success
    assert_equal "image/jpeg", response.media_type
    assert_equal bytes, response.body
    assert_equal "nosniff", response.headers["X-Content-Type-Options"]
  end

  test "returns 404 for an unlinked catalog blob" do
    blob = uploaded_blob

    get room_photo_path(blob)

    assert_response :not_found
  end

  test "returns 404 for a blob outside the upload catalog" do
    blob = uploaded_blob(content_type: "image/gif", bytes: "GIF89a", filename: "room.gif")

    get room_photo_path(blob)

    assert_response :not_found
  end

  test "returns 404 when the stored file is missing" do
    blob = uploaded_blob
    create_uploaded_room(blob)
    blob.service.delete(blob.key)

    get room_photo_path(blob)

    assert_response :not_found
  end

  test "returns 404 when stored bytes do not match the recorded size" do
    blob = uploaded_blob
    create_uploaded_room(blob)
    blob.update_column(:byte_size, blob.byte_size + 1)

    get room_photo_path(blob)

    assert_response :not_found
  end

  test "returns 404 for missing and nonnumeric ids" do
    get room_photo_path(999_999)
    assert_response :not_found

    get "/room_photos/not-a-number"
    assert_response :not_found
  end

  test "home uses the uploaded photo URL for an uploaded room" do
    blob = uploaded_blob
    room = create_uploaded_room(blob)

    get "/"

    assert_response :success
    assert_select "#booking-root[data-config]" do |elements|
      entry = JSON.parse(elements.first["data-config"])["rooms"].find do |candidate|
        candidate["id"] == room.id
      end
      assert_equal room_photo_path(blob), entry["image_url"]
    end
  end

  test "home keeps the bundled asset URL for a bundled room" do
    room = Room.create!(
      name: "Bundled Photo Room",
      description: "Bundled description.",
      capacity: 2,
      image_key: "attic"
    )

    get "/"

    assert_response :success
    assert_select "#booking-root[data-config]" do |elements|
      entry = JSON.parse(elements.first["data-config"])["rooms"].find do |candidate|
        candidate["id"] == room.id
      end
      assert_match(%r{\A/assets/house_of_horrors/room4-[0-9a-f]+\.jpg\z}, entry["image_url"])
    end
  end

  private

  def fixture_bytes
    File.binread(Rails.root.join("test/fixtures/files/room.png"))
  end

  def uploaded_blob(content_type: "image/png", bytes: nil, filename: "room.png")
    bytes ||= fixture_bytes
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new(bytes),
      filename: filename,
      content_type: content_type,
      service_name: "room_images",
      identify: false
    )
    @uploaded_blobs << blob
    blob
  end

  def create_uploaded_room(blob)
    Room.create!(
      name: "Uploaded Photo Room #{blob.id}",
      description: "Uploaded description.",
      capacity: 2,
      image_key: nil,
      image_blob: blob
    )
  end
end
