require "test_helper"
require "stringio"

class RoomTest < ActiveSupport::TestCase
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

  test "is valid with complete attributes" do
    assert build_room.valid?
  end

  test "requires name, description, capacity and exactly one image reference" do
    room = Room.new

    refute room.valid?
    assert room.errors[:name].any?
    assert room.errors[:description].any?
    assert room.errors[:capacity].any?
    assert room.errors[:base].any?
  end

  test "strips the name" do
    room = build_room(name: "  The Basement  ")

    assert room.valid?
    assert_equal "The Basement", room.name
  end

  test "rejects a name longer than 120 characters" do
    room = build_room(name: "a" * 121)

    refute room.valid?
    assert room.errors[:name].any?
  end

  test "rejects a description longer than 2000 characters" do
    room = build_room(description: "a" * 2001)

    refute room.valid?
    assert room.errors[:description].any?
  end

  test "rejects invalid and noninteger capacities" do
    [ 0, -1, 2_147_483_648, "abc", 1.5 ].each do |capacity|
      room = build_room(capacity: capacity)

      refute room.valid?, "expected capacity #{capacity.inspect} to be invalid"
      assert room.errors[:capacity].any?, "expected a capacity error for #{capacity.inspect}"
    end
  end

  test "accepts the four bundled image keys" do
    RoomImages.keys.each do |key|
      room = build_room(image_key: key)

      assert room.valid?, "expected #{key} to be valid: #{room.errors.full_messages.join(", ")}"
    end
  end

  test "rejects unknown keys and the house image" do
    [ "unknown", "house" ].each do |key|
      room = build_room(image_key: key)

      refute room.valid?, "expected #{key} to be invalid"
      assert room.errors[:image_key].any?
    end
  end

  test "accepts a valid uploaded image reference" do
    blob = uploaded_blob
    room = build_room(image_key: nil, image_blob: blob)

    assert room.valid?, room.errors.full_messages.join(", ")
    assert room.save
    assert_nil room.image_key
    assert_equal blob.id, room.image_blob_id
  end

  test "normalizes a blank image key when a blob is present" do
    room = build_room(image_key: "", image_blob: uploaded_blob)

    assert room.valid?, room.errors.full_messages.join(", ")
    assert_nil room.image_key
  end

  test "rejects missing and multiple image references" do
    missing = build_room(image_key: nil)
    both = build_room(image_key: "basement", image_blob: uploaded_blob)

    refute missing.valid?
    assert missing.errors[:base].any?
    refute both.valid?
    assert both.errors[:base].any?
  end

  test "rejects a blob outside the upload catalog" do
    blob = uploaded_blob(content_type: "image/gif", bytes: "GIF89a", filename: "room.gif")
    room = build_room(image_key: nil, image_blob: blob)

    refute room.valid?
    assert room.errors[:image_blob].any?
  end

  test "restricts deleting a referenced blob" do
    blob = uploaded_blob
    create_room(image_key: nil, image_blob: blob)

    assert_raises(ActiveRecord::InvalidForeignKey) { blob.destroy }
  end

  test "enforces exactly one image reference in the database" do
    blob = uploaded_blob
    room = create_room(image_key: nil, image_blob: blob)

    assert_raises(ActiveRecord::StatementInvalid) do
      Room.where(id: room.id).update_all(image_key: "basement")
    end
    assert_nil room.reload.image_key
  end

  test "rejects duplicate names" do
    create_room(name: "The Basement")
    duplicate = build_room(name: "The Basement")

    refute duplicate.valid?
    assert_includes duplicate.errors[:name], "has already been taken"
  end

  test "allows names that differ only by case" do
    create_room(name: "The Basement")
    other = build_room(name: "the basement")

    assert other.valid?, other.errors.full_messages.join(", ")
  end

  test "uses a binary name collation on MySQL" do
    skip "MySQL only" unless ActiveRecord::Base.connection.adapter_name == "Mysql2"

    name_field = ActiveRecord::Base.connection.select_rows("SHOW FULL FIELDS FROM rooms").find { |field| field.first == "name" }

    assert_equal "utf8mb4_0900_bin", name_field[2]
  end

  private

  def uploaded_blob(content_type: "image/png", bytes: nil, filename: "room.png")
    bytes ||= File.binread(Rails.root.join("test/fixtures/files/room.png"))
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

  def build_room(overrides = {})
    Room.new({
      name: "The Basement Where Mobile Signal Goes to Die",
      description: "You walk down the stairs and your phone gives up.",
      capacity: 10,
      image_key: "basement"
    }.merge(overrides))
  end

  def create_room(overrides = {})
    build_room(overrides).tap(&:save!)
  end
end
