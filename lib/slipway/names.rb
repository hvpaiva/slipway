# frozen_string_literal: true

require_relative 'error'

module Slipway
  # The RFC 1123 label rule kubectl applies to object names.
  module Names
    # Callers decide whether the name came from the command line or a file.
    class Invalid < Error; end

    PATTERN = /\A[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\z/
    RULE = 'lowercase letters, digits and dashes, starting and ending with a letter or digit, at most 63 characters'

    def self.valid?(name) = name.is_a?(String) && PATTERN.match?(name)

    def self.validate!(name, what: 'name')
      return name if valid?(name)

      raise Invalid, "#{name.inspect} is not a valid #{what}: #{RULE}"
    end
  end
end
