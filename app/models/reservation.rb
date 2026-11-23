class Reservation < ApplicationRecord
  SCHEDULE_MESSAGE = "Select an hourly slot from 01:00 to 07:00 UTC."
  STARTED_MESSAGE = "Select a slot that has not started."

  belongs_to :room

  validates :room, presence: true
  validate :canonical_schedule
  validate :start_in_future, if: :future_start_check?

  private

  def canonical_schedule
    start_at = start_datetime&.utc
    end_at = end_datetime&.utc

    errors.add(:base, SCHEDULE_MESSAGE) unless canonical_slot?(start_at, end_at)
  end

  def canonical_slot?(start_at, end_at)
    return false unless start_at && end_at
    return false unless start_at.usec.zero? && end_at.usec.zero?
    return false unless start_at.sec.zero? && end_at.sec.zero?
    return false unless start_at.min.zero? && end_at.min.zero?
    return false unless BookingSlots::HOURS.cover?(start_at.hour)
    return false unless end_at == start_at + 3600

    true
  end

  def start_in_future
    return if start_datetime.nil?
    return if start_datetime.utc > Time.current.utc

    errors.add(:base, STARTED_MESSAGE)
  end

  def future_start_check?
    new_record? ||
      will_save_change_to_room_id? ||
      will_save_change_to_start_datetime? ||
      will_save_change_to_end_datetime?
  end
end
