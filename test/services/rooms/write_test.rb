require "test_helper"
require "stringio"
require "timeout"
require "active_job/test_helper"
require_relative "../../support/committed_test_data"

class RoomsWriteTest < ActiveSupport::TestCase
  include CommittedTestData
  include ActiveJob::TestHelper

  setup do
    travel_to Time.utc(2026, 11, 23, 12, 0, 0)
    @time_frozen = true
    @write_room_ids = []
    @write_room_sequence = 0
    @uploaded_blobs = []
  end

  teardown do
    room_ids = @write_room_ids || []
    Reservation.where(room_id: room_ids).delete_all if room_ids.any?
    Room.where(id: room_ids).delete_all if room_ids.any?
    (@uploaded_blobs || []).each do |blob|
      ActiveStorage::Blob.where(id: blob.id).delete_all
      blob.service.delete(blob.key)
    rescue ActiveStorage::FileNotFoundError
      nil
    end
    travel_back if @time_frozen
  end

  test "creates a room with only the permitted attributes" do
    result = write(
      action: :create,
      attributes: room_attributes(
        name: "Created Write Room",
        description: "Created description.",
        capacity: 4,
        image_choice: "bundled:kitchen",
        seed_key: "ignored-seed"
      )
    )

    assert result[:ok]
    room = track(result[:record])

    assert room.persisted?
    assert_equal "Created Write Room", room.name
    assert_equal "Created description.", room.description
    assert_equal 4, room.capacity
    assert_equal "kitchen", room.image_key
    assert_nil room.image_blob_id
    assert_nil room.seed_key
  end

  test "rejects invalid create attributes without a row" do
    result = write(
      action: :create,
      attributes: room_attributes(name: "", capacity: 0, image_choice: "bundled:not-a-key")
    )

    refute result[:ok]
    assert_equal :invalid_input, result[:code]
    assert_includes result[:messages], "Select a valid room image."
    assert_equal 0, Room.where(name: "").count
  end

  test "rejects a duplicate room name" do
    commit_room!(name: "Duplicate Write Room")

    result = write(action: :create, attributes: room_attributes(name: "Duplicate Write Room"))

    refute result[:ok]
    assert_equal :invalid_input, result[:code]
    assert_includes result[:messages], "Name has already been taken"
  end

  test "updates an empty room without touching its seed key" do
    room = commit_room!(name: "Original Write Room", capacity: 3, seed_key: "keep-seed")

    result = write(
      action: :update,
      id: room.id,
      attributes: {
        name: "Edited Write Room",
        description: "Edited description.",
        capacity: 4,
        image_choice: "bundled:attic",
        seed_key: "ignored-seed"
      }
    )

    assert result[:ok]
    room.reload
    assert_equal "Edited Write Room", room.name
    assert_equal "Edited description.", room.description
    assert_equal 4, room.capacity
    assert_equal "attic", room.image_key
    assert_nil room.image_blob_id
    assert_equal "keep-seed", room.seed_key
  end

  test "preserves the room when update validation fails" do
    room = commit_room!(name: "Validated Write Room", capacity: 3)

    result = write(action: :update, id: room.id, attributes: { name: "", capacity: 0 })

    refute result[:ok]
    assert_equal :invalid_input, result[:code]
    room.reload
    assert_equal "Validated Write Room", room.name
    assert_equal 3, room.capacity
    assert_equal "basement", room.image_key
  end

  test "returns not_found for missing update and destroy ids" do
    update = write(action: :update, id: 999_999, attributes: { name: "Missing" })
    destroy = write(action: :destroy, id: 999_999)

    [ update, destroy ].each do |result|
      refute result[:ok]
      assert_equal :not_found, result[:code]
      assert_includes result[:messages], "Room not found."
    end
  end

  test "deletes an empty room" do
    room = commit_room!(name: "Empty Delete Write Room")

    result = write(action: :destroy, id: room.id)

    assert result[:ok]
    assert result[:record].destroyed?
    refute Room.exists?(room.id)
  end

  test "refuses to delete a room with a historical reservation" do
    room = nil
    travel_to Time.utc(2026, 11, 20, 12, 0, 0) do
      room = commit_room!(capacity: 2, name: "History Delete Write Room")
      start_at, end_at = BookingSlots.interval(Date.new(2026, 11, 21), 1)
      commit_reservation!(room: room, start_at: start_at, end_at: end_at)
    end

    result = write(action: :destroy, id: room.id)

    refute result[:ok]
    assert_equal :room_has_reservations, result[:code]
    assert_includes result[:messages], "Delete this room's reservations before deleting the room."
    assert Room.exists?(room.id)
    assert Reservation.exists?(room_id: room.id)
  end

  test "refuses capacity below the historical peak and allows equal or higher" do
    room = nil
    travel_to Time.utc(2026, 11, 20, 12, 0, 0) do
      room = commit_room!(capacity: 4, name: "Peak Write Room")
      start_at, end_at = BookingSlots.interval(Date.new(2026, 11, 21), 1)
      2.times { commit_reservation!(room: room, start_at: start_at, end_at: end_at) }
      other_start, other_end = BookingSlots.interval(Date.new(2026, 11, 21), 2)
      commit_reservation!(room: room, start_at: other_start, end_at: other_end)
    end

    assert_equal 2, Reservations::Occupancy.peak(room_id: room.id)

    blocked = write(action: :update, id: room.id, attributes: { capacity: 1 })

    refute blocked[:ok]
    assert_equal :capacity_below_bookings, blocked[:code]
    assert_includes blocked[:messages], "Capacity cannot be lower than the existing peak of 2."
    assert_equal 4, room.reload.capacity

    equal = write(action: :update, id: room.id, attributes: { capacity: 2 })
    assert equal[:ok]
    assert_equal 2, room.reload.capacity

    higher = write(action: :update, id: room.id, attributes: { capacity: 5 })
    assert higher[:ok]
    assert_equal 5, room.reload.capacity
  end

  test "accepts strong parameters and ignores non-allowlisted keys" do
    parameters = ActionController::Parameters.new(
      room: {
        name: "Strong Params Write Room",
        description: "Strong parameters description.",
        capacity: 2,
        image_choice: "bundled:basement",
        image_key: "attic",
        seed_key: "ignored-seed"
      }
    )

    result = write(action: :create, attributes: parameters.require(:room))

    assert result[:ok]
    room = track(result[:record])
    assert_equal "Strong Params Write Room", room.name
    assert_equal 2, room.capacity
    assert_equal "basement", room.image_key
    assert_nil room.seed_key
  end

  test "maps a unique constraint refusal to invalid input" do
    room_class = Room
    room_class.alias_method :__write_save, :save!
    room_class.define_method(:save!) { raise ActiveRecord::RecordNotUnique, "duplicate name" }

    begin
      result = write(action: :create, attributes: room_attributes(name: "Unique Race Write Room"))
    ensure
      room_class.alias_method :save!, :__write_save
      room_class.remove_method :__write_save
    end

    refute result[:ok]
    assert_equal :invalid_input, result[:code]
    assert_includes result[:messages], "Name has already been taken."
    refute Room.exists?(name: "Unique Race Write Room")
  end

  test "maps a restricted destroy to room_has_reservations" do
    room = commit_room!(name: "Restricted Destroy Write Room")
    room_class = Room
    room_class.alias_method :__write_destroy, :destroy!
    room_class.define_method(:destroy!) { raise ActiveRecord::RecordNotDestroyed.new("Room could not be destroyed", self) }

    begin
      result = write(action: :destroy, id: room.id)
    ensure
      room_class.alias_method :destroy!, :__write_destroy
      room_class.remove_method :__write_destroy
    end

    refute result[:ok]
    assert_equal :room_has_reservations, result[:code]
    assert Room.exists?(room.id)
  end

  test "rejects a caller-owned transaction" do
    room = commit_room!(name: "Caller Transaction Write Room")
    original_name = room.name

    assert_raises(ArgumentError) do
      ActiveRecord::Base.transaction do
        write(action: :update, id: room.id, attributes: { name: "Should Not Apply" })
      end
    end

    assert_equal original_name, room.reload.name
  end

  test "maps guard contention to busy without mutation" do
    room = commit_room!(name: "Busy Write Room", capacity: 2)
    original_name = room.name

    booking_write = BookingWrite.singleton_class
    booking_write.alias_method :__rooms_write_busy, :with_lock
    BookingWrite.define_singleton_method(:with_lock) { |&_block| raise BookingWrite::Busy }

    begin
      create_result = write(action: :create, attributes: room_attributes(name: "Blocked Create Room"))
      update_result = write(action: :update, id: room.id, attributes: { name: "Should Not Apply" })
      destroy_result = write(action: :destroy, id: room.id)
    ensure
      booking_write.alias_method :with_lock, :__rooms_write_busy
      booking_write.remove_method :__rooms_write_busy
    end

    [ create_result, update_result, destroy_result ].each do |result|
      refute result[:ok]
      assert_equal :busy, result[:code]
      assert_includes result[:messages], "The booking system is busy. Try again."
    end

    assert_equal original_name, room.reload.name
    assert Room.exists?(room.id)
    refute Room.exists?(name: "Blocked Create Room")
  end

  test "raises for an unsupported action" do
    assert_raises(ArgumentError) { write(action: :rename, id: 1) }
  end

  test "competing create and capacity reduction keep capacity and occupancy consistent" do
    travel_back
    @time_frozen = false

    date = future_date
    start_at, end_at = BookingSlots.interval(date, 1)
    room = commit_room!(capacity: 2, name: "Capacity Race Room")
    commit_reservation!(room: room, start_at: start_at, end_at: end_at)

    ready = Queue.new
    start = Queue.new
    results = Queue.new
    errors = Queue.new
    threads = []
    operations = [
      -> { Reservations::Create.call(room_id: room.id, date: date.iso8601, start_hour: 1) },
      -> { Rooms::Write.call(action: :update, id: room.id, attributes: { capacity: 1 }) }
    ]

    operations.each_with_index do |operation, index|
      threads << Thread.new do
        Rails.application.executor.wrap do
          ActiveRecord::Base.connection_pool.with_connection do |connection|
            ready << [ index, connection.object_id ]
            start.pop
            results << [ index, operation.call ]
          end
        end
      rescue => error
        errors << error
      ensure
        ActiveRecord::Base.connection_pool.release_connection
      end
    end

    begin
      ready_events = 2.times.map { pop_with_timeout(ready, errors) }
      refute_equal ready_events[0][1], ready_events[1][1], "the race needs two different connections"

      2.times { start << true }
      outcomes = 2.times.map { pop_with_timeout(results, errors) }.map do |index, result|
        ok = result.respond_to?(:success?) ? result.success? : result[:ok]
        { index: index, ok: ok, code: result[:code] }
      end

      successes = outcomes.count { |outcome| outcome[:ok] }
      assert_equal 1, successes

      loser = outcomes.find { |outcome| !outcome[:ok] }
      assert_includes [ :capacity_below_bookings, :slot_full, :busy ], loser[:code]

      room.reload
      occupancy = Reservation.where(room_id: room.id, start_datetime: start_at).count
      assert_includes [ [ 2, 2 ], [ 1, 1 ] ], [ room.capacity, occupancy ]
      assert_equal occupancy, occupancy_at_peak(room)
      refute Reservation.where(room_id: room.id).group(:start_datetime).count.any? { |_start_at, count|
        count > room.capacity
      }
    ensure
      2.times { start << true }
      threads.each do |thread|
        next if thread.join(15)

        thread.kill
        thread.join(5)
      end
      raise errors.pop unless errors.empty? || $!
    end
  end

  test "creates a room with an uploaded catalog image and clears the bundled key" do
    blob = uploaded_blob

    result = write(action: :create, attributes: room_attributes(image_choice: "upload:#{blob.id}"))

    assert result[:ok]
    room = track(result[:record])
    assert_nil room.image_key
    assert_equal blob.id, room.image_blob_id
    assert RoomImages.uploads.where(id: blob.id).exists?
  end

  test "switches between uploaded and bundled references without purging the blob" do
    blob = uploaded_blob
    created = write(action: :create, attributes: room_attributes(image_choice: "upload:#{blob.id}"))
    room = track(created[:record])

    bundled = nil
    assert_no_enqueued_jobs only: [ ActiveStorage::PurgeJob, ActiveRecord::DestroyAssociationAsyncJob ] do
      bundled = write(action: :update, id: room.id, attributes: { image_choice: "bundled:attic" })
    end

    assert bundled[:ok]
    room.reload
    assert_equal "attic", room.image_key
    assert_nil room.image_blob_id
    assert ActiveStorage::Blob.exists?(blob.id)
    assert blob.service.exist?(blob.key)

    reused = nil
    assert_no_enqueued_jobs only: [ ActiveStorage::PurgeJob, ActiveRecord::DestroyAssociationAsyncJob ] do
      reused = write(action: :update, id: room.id, attributes: { image_choice: "upload:#{blob.id}" })
    end

    assert reused[:ok]
    room.reload
    assert_nil room.image_key
    assert_equal blob.id, room.image_blob_id
  end

  test "keeps an uploaded blob when its last room is deleted" do
    blob = uploaded_blob
    created = write(action: :create, attributes: room_attributes(image_choice: "upload:#{blob.id}"))
    room = track(created[:record])

    result = nil
    assert_no_enqueued_jobs only: [ ActiveStorage::PurgeJob, ActiveRecord::DestroyAssociationAsyncJob ] do
      result = write(action: :destroy, id: room.id)
    end

    assert result[:ok]
    refute Room.exists?(room.id)
    assert ActiveStorage::Blob.exists?(blob.id)
    assert blob.service.exist?(blob.key)
    assert RoomImages.uploads.where(id: blob.id).exists?
  end

  test "preserves the image reference when an update omits the choice" do
    room = commit_room!(name: "Omitted Choice Write Room", capacity: 2, image_key: "kitchen")

    result = write(action: :update, id: room.id, attributes: { capacity: 4 })

    assert result[:ok]
    room.reload
    assert_equal 4, room.capacity
    assert_equal "kitchen", room.image_key
    assert_nil room.image_blob_id
  end

  test "requires an image choice when creating a room" do
    before_count = Room.count

    result = write(action: :create, attributes: room_attributes.except(:image_choice))

    refute result[:ok]
    assert_equal :invalid_input, result[:code]
    assert_includes result[:messages], "Select exactly one room image."
    assert_equal before_count, Room.count
  end

  test "rejects malformed and unknown image choices without changing the room" do
    room = commit_room!(name: "Choice Write Room", image_key: "basement")
    choices = [ "bundled:unknown", "upload:999999", "upload:abc", "nonsense", "bundled:", "upload:", "" ]

    choices.each do |choice|
      result = write(action: :update, id: room.id, attributes: { image_choice: choice })

      refute result[:ok], "expected update with #{choice.inspect} to be rejected"
      assert_equal :invalid_input, result[:code], "expected invalid_input for #{choice.inspect}"
      assert_includes result[:messages], "Select a valid room image."
    end

    room.reload
    assert_equal "basement", room.image_key
    assert_nil room.image_blob_id

    before_count = Room.count
    choices.each do |choice|
      result = write(action: :create, attributes: room_attributes(image_choice: choice))

      refute result[:ok], "expected create with #{choice.inspect} to be rejected"
      assert_equal :invalid_input, result[:code], "expected invalid_input for #{choice.inspect}"
    end
    assert_equal before_count, Room.count
  end

  private

  def write(action:, id: nil, attributes: {})
    Rooms::Write.call(action: action, id: id, attributes: attributes)
  end

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

  def room_attributes(overrides = {})
    @write_room_sequence += 1

    {
      name: "Write Room #{@write_room_sequence}",
      description: "A room used for room write tests.",
      capacity: 3,
      image_choice: "bundled:basement"
    }.merge(overrides)
  end

  def track(room)
    @write_room_ids << room.id
    room
  end

  def occupancy_at_peak(room)
    Reservation.where(room_id: room.id).group(:start_datetime).count.values.max || 0
  end

  def future_date
    Time.current.to_date + 1
  end

  def pop_with_timeout(queue, errors, timeout: 15)
    Timeout.timeout(timeout) { queue.pop }
  rescue Timeout::Error
    raise errors.pop unless errors.empty?

    raise
  end
end
