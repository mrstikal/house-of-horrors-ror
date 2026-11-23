require "test_helper"
require "timeout"
require_relative "../../support/committed_test_data"

class CreateTest < ActiveSupport::TestCase
  include CommittedTestData

  setup do
    travel_to Time.utc(2026, 11, 23, 12, 0, 0)
    @time_frozen = true
  end

  teardown do
    travel_back if @time_frozen
  end

  test "creates the first reservation" do
    room = commit_room!(capacity: 2, name: "First Place Room")
    date = future_date

    result = create_reservation(room: room, date: date, hour: 1)

    assert result.success?
    assert result[:record].persisted?
    assert_equal room.id, result[:record].room_id
    assert_equal BookingSlots.interval(date, 1).first, result[:record].start_datetime.utc
    assert_equal 1, occupancy(room, date, 1)
  end

  test "creates the last available place" do
    room = commit_room!(capacity: 2, name: "Last Place Room")
    date = future_date
    start_at, end_at = BookingSlots.interval(date, 1)
    commit_reservation!(room: room, start_at: start_at, end_at: end_at)

    result = create_reservation(room: room, date: date, hour: 1)

    assert result.success?
    assert_equal 2, occupancy(room, date, 1)
  end

  test "refuses a sequential overflow" do
    room = commit_room!(capacity: 2, name: "Overflow Room")
    date = future_date

    2.times { assert create_reservation(room: room, date: date, hour: 1).success? }
    result = create_reservation(room: room, date: date, hour: 1)

    refute result.success?
    assert_equal :slot_full, result[:code]
    assert_includes result[:messages], "This slot has just filled up. Select another time."
    assert_equal 2, occupancy(room, date, 1)
  end

  test "refuses a second booking in a one-person room" do
    room = commit_room!(capacity: 1, name: "One Person Room")
    date = future_date

    assert create_reservation(room: room, date: date, hour: 1).success?
    result = create_reservation(room: room, date: date, hour: 1)

    refute result.success?
    assert_equal :slot_full, result[:code]
    assert_equal 1, occupancy(room, date, 1)
  end

  test "keeps adjacent slots independent" do
    room = commit_room!(capacity: 1, name: "Adjacent Room")
    date = future_date

    assert create_reservation(room: room, date: date, hour: 1).success?
    assert create_reservation(room: room, date: date, hour: 2).success?
    assert_equal 1, occupancy(room, date, 1)
    assert_equal 1, occupancy(room, date, 2)
  end

  test "rejects invalid input without mutation" do
    room = commit_room!(capacity: 2, name: "Invalid Input Room")
    date = future_date
    before = Reservation.count

    [
      { room_id: "abc", date: date.iso8601, start_hour: 1 },
      { room_id: room.id, date: "not-a-date", start_hour: 1 },
      { room_id: room.id, date: date.iso8601, start_hour: 7 }
    ].each do |input|
      result = Reservations::Create.call(**input)

      refute result.success?
      assert_equal :invalid_input, result[:code]
      assert_includes result[:messages], "Select a valid room, date and hour."
    end

    assert_equal before, Reservation.count
  end

  test "rejects a missing room without mutation" do
    date = future_date
    before = Reservation.count

    result = Reservations::Create.call(room_id: 999_999, date: date.iso8601, start_hour: 1)

    refute result.success?
    assert_equal :not_found, result[:code]
    assert_includes result[:messages], "Room not found."
    assert_equal before, Reservation.count
  end

  test "rejects a started slot" do
    room = commit_room!(capacity: 2, name: "Started Slot Room")
    date = Time.current.to_date

    result = create_reservation(room: room, date: date, hour: 1)

    refute result.success?
    assert_equal :invalid_input, result[:code]
    assert_includes result[:messages], "Select a slot that has not started."
    assert_equal 0, occupancy(room, date, 1)
  end

  test "two last-place calls produce one success and one domain refusal" do
    travel_back
    @time_frozen = false

    date = future_date
    start_at, end_at = BookingSlots.interval(date, 1)
    room = commit_room!(capacity: 2, name: "Race Room")
    commit_reservation!(room: room, start_at: start_at, end_at: end_at)

    ready = Queue.new
    start = Queue.new
    results = Queue.new
    errors = Queue.new
    threads = []

    2.times do |index|
      threads << Thread.new do
        Rails.application.executor.wrap do
          ActiveRecord::Base.connection_pool.with_connection do |connection|
            ready << [ index, connection.object_id ]
            start.pop
            results << [ index, create_reservation(room: room, date: date, hour: 1) ]
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
      race_results = 2.times.map { pop_with_timeout(results, errors) }

      successes = race_results.count { |(_index, result)| result.success? }
      failures = race_results.reject { |(_index, result)| result.success? }

      assert_equal 1, successes
      assert_equal 1, failures.length
      assert_includes [ :slot_full, :busy ], failures.first[1][:code]
      assert_equal 2, Reservation.where(room_id: room.id, start_datetime: start_at).count
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

  private

  def create_reservation(room:, date:, hour:)
    Reservations::Create.call(room_id: room.id, date: date.iso8601, start_hour: hour)
  end

  def occupancy(room, date, hour)
    start_at, = BookingSlots.interval(date, hour)
    Reservation.where(room_id: room.id, start_datetime: start_at).count
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
