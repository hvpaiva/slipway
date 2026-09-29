# frozen_string_literal: true

module Slipway
  module CLI
    # Everything a command needs to talk to the outside world: the two output streams, the
    # environment, and one Style per stream so color is decided for stdout and stderr apart.
    Context = Data.define(:out, :err, :env, :tty, :err_tty, :style, :err_style) do
      def self.system
        new(out: $stdout, err: $stderr, env: ENV, tty: $stdout.tty?, err_tty: $stderr.tty?)
      end

      def initialize(out:, err:, env: {}, tty: false, err_tty: false,
                     style: Style.disabled, err_style: Style.disabled)
        super
      end

      # Resolves +mode+ (auto, always or never) once per stream.
      def with_color(mode, theme: Theme.default)
        with(style: Style.for(mode, tty:, env:, theme:),
             err_style: Style.for(mode, tty: err_tty, env:, theme:))
      end

      def puts(*lines) = out.puts(*lines)

      def print(*parts) = out.print(*parts)

      def warn(*lines) = err.puts(*lines)

      def paint(role, text) = style.paint(role, text)

      def paint_err(role, text) = err_style.paint(role, text)

      def color? = style.enabled?
    end
  end
end
