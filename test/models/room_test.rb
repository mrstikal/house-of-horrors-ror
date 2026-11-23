require "test_helper"

class RoomTest < ActiveSupport::TestCase
  test "is valid with complete attributes" do
    assert build_room.valid?
  end

  test "requires name, description, capacity and image key" do
    room = Room.new

    refute room.valid?
    assert room.errors[:name].any?
    assert room.errors[:description].any?
    assert room.errors[:capacity].any?
    assert room.errors[:image_key].any?
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
