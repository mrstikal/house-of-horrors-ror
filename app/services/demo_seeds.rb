class DemoSeeds
  class Conflict < StandardError; end

  CATALOG = [
    {
      seed_key: "basement",
      name: "The Basement Where Mobile Signal Goes to Die",
      description: "You walk down the stairs and your phone gives up. First it loses 5G, then 4G, then the will to live. In the dark, something is still buffering. It has been buffering since 2009.",
      capacity: 10
    },
    {
      seed_key: "bathroom",
      name: "The Bathroom That Judges You",
      description: "You look into the mirror. The mirror looks back. It does not scream. It sighs, very slowly, and whispers: So... this is what we are wearing today?",
      capacity: 1
    },
    {
      seed_key: "kitchen",
      name: "The Kitchen of Leftovers That Watch You Back",
      description: "You open the fridge. All the boxes turn to look at you. One of them is from Christmas. It remembers everything. It knows what you did with the potato salad.",
      capacity: 3
    },
    {
      seed_key: "attic",
      name: "The Attic Full of Clowns Doing Taxes",
      description: "You expect screaming. Instead you hear a calculator. Twelve clowns sit at a tiny table, doing taxes. One looks up and says: You did not keep your receipts, did you?",
      capacity: 6
    }
  ].freeze

  ADMIN_EMAIL = "admin@example.test"
  ADMIN_PASSWORD = "house-of-horrors-demo-2026"
  RANDOM_SEED = 20261123
  DAYS = 30

  def self.call
    new.call
  end

  def call
    unless Rails.env.development? || Rails.env.test?
      raise "DemoSeeds only runs in development and test"
    end

    outcome = BookingWrite.with_lock do
      rooms = ensure_catalog_rooms!
      ensure_admin!
      seed_reservations(rooms)
    end

    log_outcome(outcome)
    outcome
  end

  private

  def ensure_catalog_rooms!
    CATALOG.each_with_object({}) do |entry, rooms|
      room = Room.find_by(seed_key: entry[:seed_key])
      if room
        rooms[entry[:seed_key]] = room
        next
      end

      if Room.exists?(name: entry[:name])
        raise Conflict, "Cannot seed room #{entry[:seed_key]}: its default name belongs to another room."
      end

      rooms[entry[:seed_key]] = Room.create!(
        seed_key: entry[:seed_key],
        name: entry[:name],
        description: entry[:description],
        capacity: entry[:capacity],
        image_key: entry[:seed_key]
      )
    end
  end

  def ensure_admin!
    admin = User.find_by(email_address: ADMIN_EMAIL)
    if admin
      unless admin.admin?
        raise Conflict, "The demo email is already assigned to a non-admin user."
      end

      return admin
    end

    User.create!(email_address: ADMIN_EMAIL, password: ADMIN_PASSWORD, role: "admin")
  end

  def seed_reservations(rooms)
    return { status: :retained } if Reservation.exists?
    return { status: :skipped } unless canonical_capacities?(rooms)

    from = Time.current.to_date + 1
    to = from + (DAYS - 1)
    rows = build_rows(rooms, from, to)

    verify_rows!(rows)
    rows.each do |room, start_at, end_at, count|
      count.times do
        Reservation.create!(room: room, start_datetime: start_at, end_datetime: end_at)
      end
    end

    { status: :generated, from: from, to: to }
  end

  def canonical_capacities?(rooms)
    CATALOG.all? { |entry| rooms.fetch(entry[:seed_key]).capacity == entry[:capacity] }
  end

  def build_rows(rooms, from, to)
    random = Random.new(RANDOM_SEED)
    groups = {}

    (from..to).each do |date|
      CATALOG.each do |entry|
        room = rooms.fetch(entry[:seed_key])

        BookingSlots::HOURS.each do |hour|
          count = random.rand(0..room.capacity)
          count = 1 if hour == 1 && count.zero?
          set_group(groups, room, date, hour, count)
        end
      end
    end

    apply_overrides(groups, rooms, from)

    groups.values
  end

  def apply_overrides(groups, rooms, tomorrow)
    week_out = tomorrow + 6

    set_group(groups, rooms.fetch("basement"), tomorrow, 1, 9, override: true)
    set_group(groups, rooms.fetch("kitchen"), tomorrow, 1, 2, override: true)
    set_group(groups, rooms.fetch("attic"), tomorrow, 1, 5, override: true)
    set_group(groups, rooms.fetch("basement"), tomorrow, 2, 3, override: true)
    set_group(groups, rooms.fetch("basement"), tomorrow, 3, 0, override: true)

    set_group(groups, rooms.fetch("bathroom"), week_out, 2, 0, override: true)
    set_group(groups, rooms.fetch("attic"), week_out, 4, 0, override: true)

    [ 1, 2, 3, 5, 6 ].each do |hour|
      set_group(groups, rooms.fetch("attic"), week_out, hour, 6, override: true)
    end
  end

  def set_group(groups, room, date, hour, count, override: false)
    start_at, end_at = BookingSlots.interval(date, hour)
    key = [ room.id, start_at ]

    if groups.key?(key) && !override
      raise "DemoSeeds produced duplicate room/slot groups"
    end

    groups[key] = [ room, start_at, end_at, count ]
  end

  def verify_rows!(rows)
    groups = rows.map { |room, start_at, _end_at, _count| [ room.id, start_at ] }

    unless groups.length == groups.uniq.length
      raise "DemoSeeds produced duplicate room/slot groups"
    end

    rows.each do |room, _start_at, _end_at, count|
      unless count.between?(0, room.capacity)
        raise "DemoSeeds produced a count outside the room capacity"
      end
    end
  end

  def log_outcome(outcome)
    message =
      case outcome[:status]
      when :generated
        "Demo reservations generated from #{outcome[:from]} to #{outcome[:to]}."
      when :retained
        "Existing reservations retained."
      when :skipped
        "Sample occupancy skipped: canonical capacities have changed."
      end

    Rails.logger.info(message)
  end
end
