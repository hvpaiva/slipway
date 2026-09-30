# frozen_string_literal: true

module Slipway
  module CLI
    class Style
      MODES = %w[auto always never].freeze
      DEFAULT_MODE = 'auto'
      FORCE_VARIABLES = %w[FORCE_COLOR CLICOLOR_FORCE].freeze
      # C0 and C1 control characters, DEL, and the bidirectional embedding, override and isolate
      # controls: everything a terminal would obey, or use to reorder a line, instead of show.
      CONTROL = /[\x00-\x1F\x7F\u0080-\u009F\u202A-\u202E\u2066-\u2069]/
      REPLACEMENT = "\uFFFD"
      LAYOUT = "\t\n"

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

      # Painting is how slipway's own escape sequences reach a stream. Text from anywhere else is
      # made visible, so a commit subject, a git message or a manifest field can neither move the
      # cursor nor paint a STATUS of its own: C0 characters and DEL take caret notation
      # (ESC is ^[, DEL is ^?), the rest the replacement character. `layout` keeps line feeds and
      # tabs, for a message laid out on several lines such as "Did you mean this?". Under the C
      # locale Ruby hands ARGV, ENV and paths over as BINARY, which a UTF-8 pattern cannot match;
      # reading the bytes as UTF-8 keeps the valid ones and scrubs the rest.
      def self.plain(text, layout: false)
        String.new(text.to_s, encoding: Encoding::UTF_8).scrub.gsub(CONTROL) do |char|
          next char if layout && LAYOUT.include?(char)

          char.ord < 0x80 ? "^#{((char.ord + 0x40) & 0x7F).chr}" : REPLACEMENT
        end
      end

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
