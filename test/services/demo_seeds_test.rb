require "test_helper"
require_relative "../support/committed_test_data"

class DemoSeedsTest < ActiveSupport::TestCase
  include CommittedTestData

  DEMO_KEYS = %w[basement bathroom kitchen attic].freeze
  DEMO_EMAIL = "admin@example.test"

  EXPECTATIONS = [
    {
      seed_key: "basement",
      name: "The Basement Where Mobile Signal Goes to Die",
      description: "You walk down the stairs and your phone gives up. First it loses 5G, then 4G, then the will to live. In the dark, something is still buffering. It has been buffering since 2009.",
      capacity: 10,
      image_key: "basement"
    },
    {
      seed_key: "bathroom",
      name: "The Bathroom That Judges You",
      description: "You look into the mirror. The mirror looks back. It does not scream. It sighs, very slowly, and whispers: So... this is what we are wearing today?",
      capacity: 1,
      image_key: "bathroom"
    },
    {
      seed_key: "kitchen",
      name: "The Kitchen of Leftovers That Watch You Back",
      description: "You open the fridge. All the boxes turn to look at you. One of them is from Christmas. It remembers everything. It knows what you did with the potato salad.",
      capacity: 3,
      image_key: "kitchen"
    },
    {
      seed_key: "attic",
      name: "The Attic Full of Clowns Doing Taxes",
      description: "You expect screaming. Instead you hear a calculator. Twelve clowns sit at a tiny table, doing taxes. One looks up and says: You did not keep your receipts, did you?",
      capacity: 6,
      image_key: "attic"
    }
  ].freeze

  setup do
    travel_to Time.utc(2026, 11, 23, 12, 0, 0)
    @time_frozen = true
  end

  teardown do
    room_ids = Room.where(seed_key: DEMO_KEYS).pluck(:id)
    Reservation.where(room_id: room_ids).delete_all if room_ids.any?
    Room.where(id: room_ids).delete_all
    User.where(email_address: DEMO_EMAIL).delete_all
    travel_back if @time_frozen
  end

  test "seeds the catalog, admin and bounded reservations" do
    today = Time.current.to_date

    outcome = DemoSeeds.call

    assert_equal :generated, outcome[:status]
    assert_equal today + 1, outcome[:from]
    assert_equal today + 30, outcome[:to]
    assert_catalog
    assert_admin
    assert_equal today + 1, Reservation.minimum(:start_datetime).utc.to_date
    assert_equal today + 30, Reservation.maximum(:start_datetime).utc.to_date

    EXPECTATIONS.each do |expected|
      room = Room.find_by!(seed_key: expected[:seed_key])

      (today + 1..today + 30).each do |date|
        assert_operator occupancy(room, date, 1), :>=, 1,
          "expected a 01:00 booking for #{expected[:seed_key]} on #{date}"
      end
    end

    assert_overrides(today)
    assert_capacity_bounds
  end

  test "keeps rooms and reservations on a second run" do
    DemoSeeds.call
    before = reservation_counts
    room_ids = Room.where(seed_key: DEMO_KEYS).order(:id).pluck(:id)
    digest = User.find_by!(email_address: DEMO_EMAIL).password_digest

    outcome = DemoSeeds.call

    assert_equal :retained, outcome[:status]
    assert_equal before, reservation_counts
    assert_equal room_ids, Room.where(seed_key: DEMO_KEYS).order(:id).pluck(:id)
    assert_equal 4, Room.where(seed_key: DEMO_KEYS).count
    assert_equal digest, User.find_by!(email_address: DEMO_EMAIL).password_digest
  end

  test "retains reservations when run at a later date" do
    DemoSeeds.call
    before = reservation_counts

    travel_to Time.utc(2026, 12, 3, 12, 0, 0) do
      outcome = DemoSeeds.call

      assert_equal :retained, outcome[:status]
    end

    assert_equal before, reservation_counts
  end

  test "keeps an existing admin credential" do
    admin = User.create!(email_address: DEMO_EMAIL, password: "custom admin password", role: "admin")
    digest = admin.password_digest

    DemoSeeds.call

    admin.reload
    assert_equal "admin", admin.role
    assert_equal digest, admin.password_digest
    assert admin.authenticate_password("custom admin password")
    refute admin.authenticate_password("house-of-horrors-demo-2026")
  end

  test "does not overwrite admin room changes" do
    DemoSeeds.call
    room = Room.find_by!(seed_key: "basement")
    room.update!(name: "Admin Basement", description: "Admin description", capacity: 12, image_key: "attic")

    outcome = DemoSeeds.call

    assert_equal :retained, outcome[:status]
    room.reload
    assert_equal [ "Admin Basement", "Admin description", 12, "attic" ],
      [ room.name, room.description, room.capacity, room.image_key ]
    assert_equal 1, Room.where(seed_key: "basement").count
    assert_equal 4, Room.where(seed_key: DEMO_KEYS).count
  end

  test "skips sample occupancy when capacities changed and no reservations exist" do
    create_seed_rooms!(capacity_overrides: { "basement" => 11 })

    outcome = DemoSeeds.call

    assert_equal :skipped, outcome[:status]
    assert_equal 0, Reservation.count
    assert_equal 11, Room.find_by!(seed_key: "basement").capacity
    assert_equal 4, Room.where(seed_key: DEMO_KEYS).count
  end

  test "raises a conflict when a default room name is used without its seed key" do
    existing = commit_room!(
      name: "The Attic Full of Clowns Doing Taxes",
      description: "Existing attic",
      capacity: 6,
      image_key: "attic"
    )

    error = assert_raises(DemoSeeds::Conflict) { DemoSeeds.call }

    assert_equal "Cannot seed room attic: its default name belongs to another room.", error.message
    existing.reload
    assert_nil existing.seed_key
    assert_equal "Existing attic", existing.description
    assert_equal 1, Room.count
    assert_equal 0, User.count
    assert_equal 0, Reservation.count
  end

  test "refuses to promote an existing guest with the demo email" do
    guest = User.create!(email_address: DEMO_EMAIL, password: "guest password 123", role: "guest")
    digest = guest.password_digest

    error = assert_raises(DemoSeeds::Conflict) { DemoSeeds.call }

    assert_equal "The demo email is already assigned to a non-admin user.", error.message
    guest.reload
    assert_equal "guest", guest.role
    assert_equal digest, guest.password_digest
    assert_equal 1, User.count
    assert_equal 0, Room.count
    assert_equal 0, Reservation.count
  end

  test "rejects duplicate room and slot groups unless an override is explicit" do
    seeds = DemoSeeds.new
    room = Room.new(id: 123)
    date = Time.current.to_date + 1
    groups = {}

    seeds.send(:set_group, groups, room, date, 1, 2)
    error = assert_raises(RuntimeError) do
      seeds.send(:set_group, groups, room, date, 1, 3)
    end
    assert_equal "DemoSeeds produced duplicate room/slot groups", error.message

    seeds.send(:set_group, groups, room, date, 1, 3, override: true)
    assert_equal 3, groups.values.first.last
  end

  private

  def assert_catalog
    EXPECTATIONS.each do |expected|
      room = Room.find_by(seed_key: expected[:seed_key])

      assert room, "expected room #{expected[:seed_key]}"
      assert_equal expected[:name], room.name
      assert_equal expected[:description], room.description
      assert_equal expected[:capacity], room.capacity
      assert_equal expected[:seed_key], room.seed_key
      assert_equal expected[:image_key], room.image_key
    end

    assert_equal 4, Room.where(seed_key: DEMO_KEYS).count
    assert_equal DEMO_KEYS, Room.where(seed_key: DEMO_KEYS).order(:id).pluck(:seed_key)
  end

  def assert_admin
    admin = User.find_by(email_address: DEMO_EMAIL)

    assert admin, "expected the demo admin"
    assert_equal "admin", admin.role
    assert admin.authenticate_password("house-of-horrors-demo-2026")
  end

  def assert_overrides(today)
    tomorrow = today + 1
    week_out = today + 7

    {
      [ "basement", tomorrow, 1 ] => 9,
      [ "kitchen", tomorrow, 1 ] => 2,
      [ "attic", tomorrow, 1 ] => 5,
      [ "basement", tomorrow, 2 ] => 3,
      [ "basement", tomorrow, 3 ] => 0,
      [ "bathroom", week_out, 2 ] => 0,
      [ "attic", week_out, 4 ] => 0,
      [ "attic", week_out, 1 ] => 6,
      [ "attic", week_out, 2 ] => 6,
      [ "attic", week_out, 3 ] => 6,
      [ "attic", week_out, 5 ] => 6,
      [ "attic", week_out, 6 ] => 6
    }.each do |(seed_key, date, hour), expected|
      room = Room.find_by!(seed_key: seed_key)

      assert_equal expected, occupancy(room, date, hour), "unexpected count for #{seed_key} on #{date} at #{hour}"
    end
  end

  def assert_capacity_bounds
    capacities = Room.where(seed_key: DEMO_KEYS).pluck(:id, :capacity).to_h

    reservation_counts.each do |(room_id, start_at), count|
      capacity = capacities[room_id]

      assert capacity, "unexpected room #{room_id}"
      assert_operator count, :<=, capacity
      assert_equal 0, start_at.min
      assert_equal 0, start_at.sec
      assert_includes BookingSlots::HOURS, start_at.hour
    end
  end

  def reservation_counts
    Reservation.group(:room_id, :start_datetime).count
  end

  def occupancy(room, date, hour)
    start_at, = BookingSlots.interval(date, hour)
    Reservation.where(room_id: room.id, start_datetime: start_at).count
  end

  def create_seed_rooms!(capacity_overrides: {})
    EXPECTATIONS.each do |expected|
      commit_room!(
        seed_key: expected[:seed_key],
        name: expected[:name],
        description: expected[:description],
        capacity: capacity_overrides.fetch(expected[:seed_key], expected[:capacity]),
        image_key: expected[:image_key]
      )
    end
  end
end
