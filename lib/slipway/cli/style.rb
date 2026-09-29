# frozen_string_literal: true

module Slipway
  module CLI
    class Style
      MODES = %w[auto always never].freeze
      DEFAULT_MODE = 'auto'
      FORCE_VARIABLES = %w[FORCE_COLOR CLICOLOR_FORCE].freeze

      attr_reader :theme

      def self.for(mode, tty:, env:, theme: Theme.default)
        new(enabled: enabled?(mode, tty:, env:), theme:)
      end

      def self.enabled?(mode, tty:, env:)
        case mode
        when 'always' then true
        when 'never' then false
        else auto?(tty:, env:)
        end
      end

      def self.auto?(tty:, env:)
        return false if set?(env['NO_COLOR'])
        return true if FORCE_VARIABLES.any? { set?(env[it]) }
        return false if env['TERM'] == 'dumb'

        tty
      end

      def self.set?(value) = !value.to_s.empty?

      private_class_method :enabled?, :auto?, :set?

      def self.disabled = new(enabled: false, theme: Theme.default)

      def initialize(enabled:, theme:)
        @enabled = enabled
        @theme = theme
      end

      def enabled? = @enabled

      def paint(role, text)
        wrap(theme.sgr(role), text)
      end

      def paint_cycle(role, index, text)
        wrap(theme.sgr_at(role, index), text)
      end

      private

      def wrap(sgr, text)
        return text.to_s unless @enabled

        "\e[#{sgr}m#{text}\e[0m"
      end
    end
  end
end
