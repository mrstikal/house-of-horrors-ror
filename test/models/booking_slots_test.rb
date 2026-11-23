require "test_helper"

class BookingSlotsTest < ActiveSupport::TestCase
  test "exposes the six hourly slots" do
    assert_equal (1..6), BookingSlots::HOURS
  end

  test "parses strict ISO dates" do
    assert_equal Date.new(2026, 11, 24), BookingSlots.parse_date("2026-11-24")
    assert_equal Date.new(2028, 2, 29), BookingSlots.parse_date("2028-02-29")
  end

  test "rejects malformed and partial dates" do
    [ nil, "", "2026-11-2", "2026-1-24", "2026/11/24", "20261124", "2026-11-24T00:00:00Z",
      " 2026-11-24", "2026-11-24 ", "2026-02-30", "2027-02-29" ].each do |value|
      assert_nil BookingSlots.parse_date(value), "expected #{value.inspect} to be rejected"
    end
  end

  test "rejects dates outside the supported year range" do
    assert_nil BookingSlots.parse_date("0999-12-31")
    assert_equal Date.iso8601("1000-01-01", Date::GREGORIAN), BookingSlots.parse_date("1000-01-01")
    assert_equal Date.iso8601("9998-12-31", Date::GREGORIAN), BookingSlots.parse_date("9998-12-31")
    assert_nil BookingSlots.parse_date("9999-01-01")
  end

  test "parses only the six canonical hours" do
    BookingSlots::HOURS.each do |hour|
      assert_equal hour, BookingSlots.parse_hour(hour)
      assert_equal hour, BookingSlots.parse_hour(hour.to_s)
    end

    [ 0, 7, -1, "0", "7", "01", "1.0", 1.0, nil, " 1", "1 " ].each do |value|
      assert_nil BookingSlots.parse_hour(value), "expected #{value.inspect} to be rejected"
    end
  end

  test "builds one-hour UTC intervals" do
    date = Date.new(2026, 11, 24)

    assert_equal [ Time.utc(2026, 11, 24, 1), Time.utc(2026, 11, 24, 2) ], BookingSlots.interval(date, 1)
    assert_equal [ Time.utc(2026, 11, 24, 6), Time.utc(2026, 11, 24, 7) ], BookingSlots.interval(date, 6)
  end

  test "keeps six UTC slots on a DST change date" do
    date = BookingSlots.parse_date("2026-03-29")

    intervals = BookingSlots::HOURS.map { |hour| BookingSlots.interval(date, hour) }

    assert_equal 6, intervals.length
    assert_equal (1..6).map { |hour| Time.utc(2026, 3, 29, hour) }, intervals.map(&:first)
    intervals.each { |start_at, end_at| assert_equal 3600, end_at - start_at }
  end

  test "parses positive IDs up to the signed 64-bit maximum" do
    assert_equal 1, BookingSlots.parse_id(1)
    assert_equal 1, BookingSlots.parse_id("1")
    assert_equal 9_223_372_036_854_775_807, BookingSlots.parse_id("9223372036854775807")

    [ 0, -1, "0", "-1", "abc", "1.0", 1.0, nil, "9223372036854775808", "12345678901234567890" ].each do |value|
      assert_nil BookingSlots.parse_id(value), "expected #{value.inspect} to be rejected"
    end
  end
end
