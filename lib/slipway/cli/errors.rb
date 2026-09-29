# frozen_string_literal: true

module Slipway
  # Base class for every failure Slipway reports to the user; exits with status 1.
  class Error < StandardError
    def exit_status = 1

    # Usage errors point at a help page; every other error prints its message alone.
    def hint = nil
  end

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

      def exit_status = 2
    end
  end
end
