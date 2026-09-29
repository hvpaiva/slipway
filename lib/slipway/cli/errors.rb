# frozen_string_literal: true

require_relative '../error'

module Slipway
  module CLI
    # Raised when the command line itself is wrong; exits with status 2.
    class UsageError < Slipway::Error
      # A one-line pointer to the relevant help, printed after the message. The Runner
      # fills it in from the resolved command path when a handler leaves it nil.
      attr_reader :hint

      def initialize(message, hint: nil)
        super(message)
        @hint = hint
      end

      # Usage errors exit with 2, the status the man page reserves for a wrong command line.
      def exit_status = 2
    end
  end
end
