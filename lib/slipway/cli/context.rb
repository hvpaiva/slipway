# frozen_string_literal: true

require_relative 'style'
require_relative 'theme'

module Slipway
  module CLI
    # Everything a command needs to talk to the outside world: the two output streams, the
    # environment, and one Style per stream so color is decided for stdout and stderr apart.
    # A stream whose reader went away is remembered and its later output dropped, so a
    # command finishes its work when `head` exits or a wrapper closed stderr.
    class Context
      attr_reader :out, :err, :env, :tty, :err_tty, :style, :err_style

      # The process's own streams and environment.
      def self.system
        new(out: $stdout, err: $stderr, env: ENV, tty: $stdout.tty?, err_tty: $stderr.tty?)
      end

      def initialize(out:, err:, env: {}, tty: false, err_tty: false,
                     style: Style.disabled, err_style: Style.disabled)
        @out = out
        @err = err
        @env = env
        @tty = tty
        @err_tty = err_tty
        @style = style
        @err_style = err_style
        @closed = {}
      end

      # A copy with +mode+ (auto, always or never) resolved once per stream; the copy shares
      # this context's memory of closed streams.
      def with_color(mode, theme: Theme.default)
        dup.tap { it.restyle(Style.for(mode, tty:, env:, theme:), Style.for(mode, tty: err_tty, env:, theme:)) }
      end

      # Writes +lines+ to stdout, each followed by a newline.
      def puts(*lines) = write(:out) { out.puts(*lines) }

      # Writes +parts+ to stdout as given.
      def print(*parts) = write(:out) { out.print(*parts) }

      # Writes +lines+ to stderr, each followed by a newline.
      def warn(*lines) = write(:err) { err.puts(*lines) }

      # +text+ in the SGR sequence +role+ has for stdout, or unchanged when color is off there.
      def paint(role, text) = style.paint(role, text)

      # +text+ in the SGR sequence +role+ has for stderr, or unchanged when color is off there.
      def paint_err(role, text) = err_style.paint(role, text)

      # True when stdout is painted.
      def color? = style.enabled?

      protected

      def restyle(style, err_style)
        @style = style
        @err_style = err_style
      end

      private

      def write(stream)
        return if @closed[stream]

        yield
      rescue Errno::EPIPE
        @closed[stream] = true
      end
    end
  end
end
