class BookingWrite
  class Busy < StandardError; end

  def self.with_lock
    ApplicationRecord.connection_pool.with_connection do |connection|
      if connection.transaction_open?
        raise ArgumentError, "BookingWrite.with_lock cannot run inside a caller-owned transaction"
      end

      rolled_back = false

      result = ApplicationRecord.uncached do
        transaction(connection) do
          BookingWriteLock.upsert(
            { id: 1, token: 0 },
            on_duplicate: Arel.sql("token = 1 - booking_write_locks.token"),
            record_timestamps: false
          )

          begin
            yield
          rescue ActiveRecord::Rollback
            rolled_back = true
            raise
          end
        end
      end

      raise ActiveRecord::Rollback if rolled_back

      result
    end
  rescue ActiveRecord::Deadlocked, ActiveRecord::LockWaitTimeout, ActiveRecord::StatementTimeout
    raise Busy
  rescue SQLite3::LockedException
    raise Busy
  rescue ActiveRecord::StatementInvalid => error
    raise Busy if error.cause.is_a?(SQLite3::LockedException)

    raise
  end

  def self.transaction(connection, &block)
    if connection.adapter_name == "Mysql2"
      connection.transaction(isolation: :read_committed, &block)
    else
      connection.transaction(&block)
    end
  end

  private_class_method :transaction
end
