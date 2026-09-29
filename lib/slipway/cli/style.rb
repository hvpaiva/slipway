# frozen_string_literal: true

module Slipway
  module CLI
    # Paints text with the SGR codes of a Theme, or returns it untouched when color is off.
    class Style
      MODES = %w[auto always never].freeze
      DEFAULT_MODE = 'auto'
      FORCE_VARIABLES = %w[FORCE_COLOR CLICOLOR_FORCE].freeze

      attr_reader :theme

      # Resolves a color mode for one stream. An explicit +always+ or +never+ wins; in
      # +auto+, NO_COLOR disables, then FORCE_COLOR or CLICOLOR_FORCE enables, then
      # TERM=dumb disables, and otherwise the stream's tty flag decides.
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

      # Returns +mode+ when it names a color mode or raises Slipway::Error for anything else.
      def self.fetch_mode(mode)
        return mode if MODES.include?(mode)

        raise Slipway::Error, "unknown color mode #{mode.inspect} (known modes: #{MODES.join(', ')})"
      end

      # A Style that paints nothing, for streams whose color has not been decided yet.
      def self.disabled = new(enabled: false, theme: Theme.default)

      def initialize(enabled:, theme:)
        @enabled = enabled
        @theme = theme
      end

      def enabled? = @enabled

      # Wraps +text+ in the SGR sequence of a single-valued role.
      def paint(role, text)
        wrap(theme.sgr(role), text)
      end

      # Paints with the +index+-th color of a list role, such as a table column.
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
