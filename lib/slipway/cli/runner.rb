# frozen_string_literal: true

module Slipway
  module CLI
    # Front controller: parses the global prefix, walks the command tree, parses the
    # command's options, validates against the registry and dispatches. Returns the exit
    # status and never lets an exception escape as a backtrace.
    class Runner
      SIGINT_STATUS = 130
      EPIPE_STATUS = 0
      UNEXPECTED_STATUS = 1
      COLOR_VARIABLE = 'SLIPWAY_COLOR'
      THEME_VARIABLE = 'SLIPWAY_THEME'
      DEBUG_VARIABLE = 'SLIPWAY_DEBUG'

      # +color+ and +theme+ are the fallbacks used when neither a flag nor the environment
      # decides, which is where the configuration file values arrive.
      def initialize(registry, context, color: nil, theme: nil)
        @registry = registry
        @context = context
        @default_color = color
        @default_theme = theme
      end

      # Runs one command line and returns its exit status.
      def run(argv)
        execute(argv.dup)
      rescue Errno::EPIPE
        EPIPE_STATUS
      end

      private

      # Maps every failure to its exit status. A broken pipe is left for +run+, so one
      # raised while reporting another error still exits quietly.
      def execute(argv)
        dispatch(argv)
      rescue Errno::EPIPE
        raise
      rescue Slipway::Error => e
        report(e.message, e.hint)
        e.exit_status
      rescue Interrupt
        @context.err.write("\n")
        SIGINT_STATUS
      rescue StandardError => e
        report_unexpected(e)
        UNEXPECTED_STATUS
      end

      def dispatch(argv)
        values = {}
        command, path, rest = walk(argv, values)
        return run_raw(command, rest) if command.raw

        args = parse(@registry.globals + command.options, path, values) { it.permute!(rest) }
        opts = defaults(command, values)
        return show_help(command, path) if opts[:help]
        return show_version if opts[:version]
        return show_help(command, path) if command.group?

        Validator.new(command, path, @registry).call(args, opts)
        invoke(command, path, args, opts)
      end

      # Consumes `[GLOBALS] WORD` repeatedly until a leaf command is reached, so global
      # flags may appear before the verb and between a group and its subcommand.
      def walk(argv, values)
        command = @registry.root
        path = []
        while command.group?
          argv = parse(@registry.globals, path, values) { it.order!(argv) }
          word = argv.shift
          return [command, path, argv] if word.nil?

          command = command.find(word) or raise unknown_command(word, path)
          path << word
        end
        [command, path, argv]
      end

      def unknown_command(word, path)
        UsageError.new(@registry.unknown_command(word, path), hint: @registry.run_hint(path))
      end

      # Color is re-resolved after every parse step, so a `--color` anywhere on the line
      # also applies to the error that may follow it.
      def parse(options, path, values)
        parser = Parser.new(options, values)
        yield parser
      rescue OptionParser::InvalidOption => e
        raise UsageError.new(@registry.unknown_option(e.args.first, options), hint: @registry.help_hint(path))
      rescue OptionParser::ParseError => e
        raise UsageError.new(e.message, hint: @registry.help_hint(path))
      ensure
        colorize(values)
      end

      def defaults(command, values)
        Parser.new(@registry.globals + command.options, values).defaults.freeze
      end

      # The flag value is taken as given here; the Validator reports an unknown one later.
      def colorize(values)
        @context = @context.with_color(values.fetch(:color) { fallback_color }, theme:)
      end

      def fallback_color
        @fallback_color ||= Style.fetch_mode(environment(COLOR_VARIABLE) || @default_color || Style::DEFAULT_MODE)
      end

      def theme
        @theme ||= Theme.fetch(environment(THEME_VARIABLE) || @default_theme || Theme::DEFAULT_NAME)
      end

      def environment(name)
        value = @context.env[name]
        value unless value.to_s.empty?
      end

      # A handler may raise UsageError without a hint; the hint then points at its own help.
      def invoke(command, path, args, opts)
        command.handler.call(@context, args, opts)
        0
      rescue UsageError => e
        raise if e.hint

        raise UsageError.new(e.message, hint: @registry.help_hint(path))
      end

      def run_raw(command, rest)
        command.handler.call(@context, rest, {})
        0
      end

      def show_help(command, path)
        renderer = HelpRenderer.new(@registry, @context.style)
        @context.print(command.equal?(@registry.root) ? renderer.root : renderer.command(command, path))
        0
      end

      def show_version
        @context.puts(Builtins.version_line(@registry.program, @registry.version))
        0
      end

      def report(message, hint)
        @context.warn("#{@context.paint_err(:error, 'error:')} #{message}")
        @context.warn(hint) if hint
      end

      def report_unexpected(error)
        report(error.message, nil)
        return unless environment(DEBUG_VARIABLE)

        @context.warn(error.class.name, *Array(error.backtrace).map { "    #{it}" })
      end
    end
  end
end
