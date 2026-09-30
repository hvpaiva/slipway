# frozen_string_literal: true

require_relative '../error'

module Slipway
  module Git
    # A subset of what `git check-ref-format --branch` accepts, closed so that a name can never
    # read as an option or carry a control character.
    module BranchName
      # Callers decide whether the name came from the command line or a file.
      class Invalid < Slipway::Error; end

      PATTERN = %r{\A[A-Za-z0-9][A-Za-z0-9._/-]*\z}
      FORBIDDEN = %r{\.\.|//|/\.|\.lock(?:/|\z)|[/.]\z}
      MAX = 255
      RULE = 'letters, digits, ".", "_", "/" and "-", starting with a letter or digit, at most 255 characters, ' \
             'with no "..", no "//", no component that starts with "." or ends with ".lock", no trailing "/" ' \
             'or ".", and not HEAD'

      def self.valid?(name)
        name.is_a?(String) && name.valid_encoding? && name.size <= MAX && name != 'HEAD' &&
          PATTERN.match?(name) && !FORBIDDEN.match?(name)
      end

      def self.validate!(name)
        return name if valid?(name)

        raise Invalid, "#{name.scrub.inspect} is not a valid branch name: #{RULE}"
      end
    end
  end
end
