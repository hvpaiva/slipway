# frozen_string_literal: true

require_relative '../error'

module Slipway
  module CLI
    class UsageError < Slipway::Error
      STATUS = 2

      # A nil hint is filled in by the Runner from the resolved command path.
      attr_reader :hint

      def initialize(message, hint: nil)
        super(message)
        @hint = hint
      end

      def exit_status = STATUS
    end
  end
end
