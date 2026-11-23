require "test_helper"
require "timeout"
require_relative "../support/committed_test_data"

class BookingWriteTest < ActiveSupport::TestCase
  include CommittedTestData

  setup do
    BookingWriteLock.delete_all
  end

  test "inserts the lock row on the first guarded call" do
    assert_equal 0, BookingWriteLock.count

    result = BookingWrite.with_lock { :done }

    assert_equal :done, result
    assert_equal 0, BookingWriteLock.find(1).token
  end

  test "commits a guarded block" do
    room = commit_room!

    BookingWrite.with_lock { room.update!(name: "Committed Room") }

    assert_equal "Committed Room", room.reload.name
  end

  test "rolls back a guarded block that raises" do
    room = commit_room!
    original_name = room.name

    assert_raises(RuntimeError) do
      BookingWrite.with_lock do
        room.update!(name: "Rolled Back Room")
        raise "boom"
      end
    end

    assert_equal original_name, room.reload.name
  end

  test "does not report success when the guarded block rolls back" do
    room = commit_room!
    original_name = room.name

    assert_raises(ActiveRecord::Rollback) do
      BookingWrite.with_lock do
        room.update!(name: "Rolled Back Room")
        raise ActiveRecord::Rollback
      end
    end

    assert_equal original_name, room.reload.name
  end

  test "refuses a caller-owned transaction" do
    assert_raises(ArgumentError) do
      ActiveRecord::Base.transaction do
        BookingWrite.with_lock { flunk "the guarded block must not run" }
      end
    end
  end

  test "times out a competing guard and then commits a later call" do
    expected_adapter = ENV.fetch("HOH_DB", "sqlite") == "mysql" ? "Mysql2" : "SQLite"
    assert_equal expected_adapter, ActiveRecord::Base.connection.adapter_name

    room = commit_room!
    original_name = room.name
    acquired = Queue.new
    release = Queue.new
    result = Queue.new
    errors = Queue.new
    thread_a = nil
    thread_b = nil

    thread_a = Thread.new do
      Rails.application.executor.wrap do
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          BookingWrite.with_lock do
            acquired << connection.object_id
            release.pop
          end
        end
      end
    rescue => error
      errors << error
    ensure
      ActiveRecord::Base.connection_pool.release_connection
    end

    connection_id_a = pop_with_timeout(acquired, errors)

    thread_b = Thread.new do
      Rails.application.executor.wrap do
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          ran = false
          busy = nil
          begin
            BookingWrite.with_lock do
              ran = true
              room.update!(name: "Should never run")
            end
          rescue BookingWrite::Busy => error
            busy = error
          end
          result << [ connection.object_id, busy, ran ]
        end
      end
    rescue => error
      errors << error
    ensure
      ActiveRecord::Base.connection_pool.release_connection
    end

    connection_id_b, busy, ran = pop_with_timeout(result, errors)

    assert_instance_of BookingWrite::Busy, busy
    refute ran, "the competing guarded block must not run"
    refute_equal connection_id_a, connection_id_b
    assert_equal original_name, room.reload.name

    release << true
    assert thread_a.join(15), "the first guard did not finish after release"
    assert thread_b.join(15), "the competing guard did not finish"
    raise errors.pop unless errors.empty?

    BookingWrite.with_lock { room.update!(name: "After contention") }
    assert_equal "After contention", room.reload.name
  ensure
    release << true if release
    thread_a&.join(15)
    thread_a&.kill if thread_a&.alive?
    thread_b&.join(15)
    thread_b&.kill if thread_b&.alive?
  end

  private

  def pop_with_timeout(queue, errors, timeout: 15)
    Timeout.timeout(timeout) { queue.pop }
  rescue Timeout::Error
    raise errors.pop unless errors.empty?

    raise
  end
end
