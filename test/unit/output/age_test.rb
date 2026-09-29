# frozen_string_literal: true

require 'test_helper'

class AgeTest < Minitest::Test
  NOW = Time.utc(2026, 9, 29, 12, 0, 0)
  MINUTE = 60
  HOUR = 60 * MINUTE
  DAY = 24 * HOUR
  YEAR = 365 * DAY

  def test_seconds_up_to_two_minutes
    assert_equal '0s', age(0)
    assert_equal '1s', age(1)
    assert_equal '119s', age(119)
  end

  def test_minutes_with_seconds_under_ten_minutes
    assert_equal '2m', age(120)
    assert_equal '2m1s', age(121)
    assert_equal '5m30s', age((5 * MINUTE) + 30)
    assert_equal '9m59s', age((9 * MINUTE) + 59)
  end

  def test_whole_minutes_under_three_hours
    assert_equal '10m', age(10 * MINUTE)
    assert_equal '10m', age((10 * MINUTE) + 30)
    assert_equal '179m', age(179 * MINUTE)
  end

  def test_hours_with_minutes_under_eight_hours
    assert_equal '3h', age(180 * MINUTE)
    assert_equal '3h15m', age((3 * HOUR) + (15 * MINUTE))
    assert_equal '7h59m', age((7 * HOUR) + (59 * MINUTE))
    assert_equal '7h59m', age((7 * HOUR) + (59 * MINUTE) + 59)
  end

  def test_whole_hours_under_two_days
    assert_equal '8h', age(8 * HOUR)
    assert_equal '47h', age(47 * HOUR)
    assert_equal '47h', age((47 * HOUR) + (59 * MINUTE))
  end

  def test_days_with_hours_under_eight_days
    assert_equal '2d', age(48 * HOUR)
    assert_equal '3d4h', age((3 * DAY) + (4 * HOUR))
    assert_equal '7d23h', age((7 * DAY) + (23 * HOUR))
  end

  def test_whole_days_under_two_years
    assert_equal '8d', age(8 * DAY)
    assert_equal '8d', age((8 * DAY) + (5 * HOUR))
    assert_equal '400d', age(400 * DAY)
    assert_equal '729d', age(729 * DAY)
  end

  def test_years_with_days_under_eight_years
    assert_equal '2y', age(2 * YEAR)
    assert_equal '2y30d', age((2 * YEAR) + (30 * DAY))
    assert_equal '7y364d', age((7 * YEAR) + (364 * DAY))
  end

  def test_whole_years_from_eight_years_on
    assert_equal '8y', age(8 * YEAR)
    assert_equal '9y', age((9 * YEAR) + (100 * DAY))
  end

  def test_small_clock_skew_reads_as_zero_and_larger_skew_as_invalid
    assert_equal '0s', age(-0.5)
    assert_equal '0s', age(-1)
    assert_equal '<invalid>', age(-2)
    assert_equal '<invalid>', age(-DAY)
  end

  def test_fractions_of_a_second_are_truncated
    assert_equal '119s', Slipway::Output::Age.format(119.9)
    assert_equal '2m', Slipway::Output::Age.format(120.4)
  end

  def test_humanize_returns_nil_for_an_unknown_start
    assert_nil Slipway::Output::Age.humanize(nil, NOW)
  end

  private

  def age(seconds) = Slipway::Output::Age.humanize(NOW - seconds, NOW)
end
