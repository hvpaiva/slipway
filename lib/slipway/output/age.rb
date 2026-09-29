# frozen_string_literal: true

module Slipway
  module Output
    # Formats an elapsed time the way kubectl's AGE column does: two units at most, the
    # precision dropping as the duration grows, and integer truncation at every step.
    module Age
      INVALID = '<invalid>'
      MINUTE = 60
      HOUR = 60
      DAY = 24
      YEAR = 365

      # Age of +from+ as seen at +to+, or nil when +from+ is unknown.
      def self.humanize(from, to)
        return nil if from.nil?

        format(to - from)
      end

      # Formats a duration given in +seconds+. Anything two or more seconds in the future
      # is reported as invalid; a little clock skew rounds to zero.
      def self.format(seconds)
        seconds = seconds.to_i
        return INVALID if seconds < -1
        return '0s' if seconds.negative?
        return "#{seconds}s" if seconds < 2 * MINUTE

        from_minutes(seconds)
      end

      def self.from_minutes(seconds)
        minutes = seconds / MINUTE
        return pair(minutes, 'm', seconds % MINUTE, 's') if minutes < 10
        return "#{minutes}m" if minutes < 3 * HOUR

        from_hours(minutes)
      end

      def self.from_hours(minutes)
        hours = minutes / HOUR
        return pair(hours, 'h', minutes % HOUR, 'm') if hours < 8
        return "#{hours}h" if hours < 2 * DAY

        from_days(hours)
      end

      def self.from_days(hours)
        days = hours / DAY
        return pair(days, 'd', hours % DAY, 'h') if days < 8
        return "#{days}d" if days < 2 * YEAR

        from_years(days)
      end

      def self.from_years(days)
        years = days / YEAR
        return pair(years, 'y', days % YEAR, 'd') if years < 8

        "#{years}y"
      end

      # Two units, the smaller one omitted when it is zero: "3h15m" but "3h".
      def self.pair(major, major_unit, minor, minor_unit)
        return "#{major}#{major_unit}" if minor.zero?

        "#{major}#{major_unit}#{minor}#{minor_unit}"
      end

      private_class_method :from_minutes, :from_hours, :from_days, :from_years, :pair
    end
  end
end
