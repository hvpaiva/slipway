# frozen_string_literal: true

require_relative 'cli/errors'

module Slipway
  # Validates project and group names against the RFC 1123 label rule kubectl applies to object names.
  module Names
    PATTERN = /\A[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\z/
    RULE = 'lowercase letters, digits and dashes, starting and ending with a letter or digit, at most 63 characters'

    def self.valid?(name) = name.is_a?(String) && PATTERN.match?(name)

    # Returns +name+ or raises Slipway::Error; +what+ names the field in the message.
    def self.validate!(name, what: 'name')
      return name if valid?(name)

      raise Error, "#{name.inspect} is not a valid #{what}: #{RULE}"
    end
  end
end
