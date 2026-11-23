module BookingSlots
  HOURS = (1..6).freeze
  MAX_ID = 9_223_372_036_854_775_807

  def self.parse_date(value)
    return nil unless value.is_a?(String)
    return nil unless value.ascii_only?
    return nil unless value.match?(/\A[0-9]{4}-[0-9]{2}-[0-9]{2}\z/)

    date = Date.iso8601(value, Date::GREGORIAN)
    return nil unless date.year.between?(1000, 9998)

    date
  rescue Date::Error
    nil
  end

  def self.parse_hour(value)
    case value
    when Integer
      value if HOURS.cover?(value)
    when String
      value.to_i if value.match?(/\A[1-6]\z/)
    end
  end

  def self.interval(date, hour)
    start_at = Time.utc(date.year, date.month, date.day, hour)

    [ start_at, start_at + 3600 ]
  end

  def self.parse_id(value)
    case value
    when Integer
      value if value.positive? && value <= MAX_ID
    when String
      return nil unless value.match?(/\A[0-9]{1,19}\z/)

      id = value.to_i
      id if id.positive? && id <= MAX_ID
    end
  end
end
