# frozen_string_literal: true

module Slipway
  module CLI
    # One command-line option. +long+ is the name without dashes and +argument+ the
    # placeholder shown in help (nil for a boolean flag). An +optional+ option takes its
    # argument only as --long=VALUE and stores +implicit+ when the value is omitted;
    # +completer+ is a proc returning candidate values for shell completion.
    Option = Data.define(:long, :short, :argument, :enum, :default, :description,
                         :repeatable, :required, :optional, :implicit, :completer) do
      def initialize(long:, description:, short: nil, argument: nil, enum: nil, default: nil,
                     repeatable: false, required: false, optional: false, implicit: nil, completer: nil)
        super
      end

      # The Hash key parsed values are stored under: --no-headers becomes :no_headers.
      def key = long.tr('-', '_').to_sym

      def flag? = argument.nil?

      def switches = [short && "-#{short}", "--#{long}"].compact

      # The spec OptionParser#on understands: ["-o", "--output FORMAT"].
      def switch_spec
        long_spec = if flag? then "--#{long}"
                    elsif optional then "--#{long}[=#{argument}]"
                    else "--#{long} #{argument}"
                    end
        [short && "-#{short}", long_spec].compact
      end

      # How the option reads in help and error messages: "-o, --output FORMAT".
      def label
        text = switches.join(', ')
        return text if flag?

        optional ? "#{text}[=#{argument}]" : "#{text} #{argument}"
      end

      # Folds one parsed occurrence into the value stored so far.
      def accept(current, raw)
        return true if flag?
        return implicit if optional && raw.nil?
        return Array(current) << raw if repeatable

        raw
      end

      # Completion values: the enum when there is one, else whatever the completer returns.
      def candidates(given = []) = enum || completer&.call(given) || []

      # Plain data for generators; the completer proc becomes a marker.
      def manifest
        to_h.except(:completer).merge(key: key, completer: completer ? 'dynamic' : nil)
      end
    end

    # One positional argument. A variadic positional absorbs every remaining word.
    Positional = Data.define(:name, :required, :variadic, :enum, :completer) do
      def initialize(name:, required: true, variadic: false, enum: nil, completer: nil)
        super
      end

      # How the positional reads in a usage line: NAME, [NAME] or NAME...
      def usage
        token = variadic ? "#{name}..." : name
        required ? token : "[#{token}]"
      end

      def candidates(given = []) = enum || completer&.call(given) || []

      def manifest = to_h.except(:completer).merge(completer: completer ? 'dynamic' : nil)
    end

    # A help example: a comment line and the command line it illustrates, without the program name.
    Example = Data.define(:comment, :command)

    # A verb, or a group of verbs when +subcommands+ is non-empty. +handler+ responds to
    # call(context, args, opts). A +raw+ command receives argv untouched, with no option
    # parsing, which is what the completion endpoint needs.
    Command = Data.define(:name, :aliases, :summary, :description, :section, :examples,
                          :positionals, :options, :subcommands, :hidden, :raw, :handler) do
      def initialize(name:, summary:, description: nil, aliases: [], section: 'Available Commands', examples: [],
                     positionals: [], options: [], subcommands: [], hidden: false, raw: false, handler: nil)
        super(name:, summary:, description: description || summary, aliases:, section:, examples:,
              positionals:, options:, subcommands:, hidden:, raw:, handler:)
      end

      def group? = !subcommands.empty?

      def names = [name, *aliases]

      # The subcommand called +word+ by name or alias, or nil.
      def find(word) = subcommands.find { it.names.include?(word) }

      def visible_subcommands = subcommands.reject(&:hidden)

      # The positional that receives the argument at +index+; a variadic tail absorbs the rest.
      def positional_at(index) = positionals[index] || (positionals.last if positionals.last&.variadic)

      def min_args = positionals.count(&:required)

      def max_args = positionals.last&.variadic ? nil : positionals.size

      def usage_args
        return 'COMMAND' if group?

        positionals.map(&:usage).join(' ')
      end

      # Plain data for generators, without the handler.
      def manifest
        to_h.except(:handler).merge(
          positionals: positionals.map(&:manifest),
          options: options.map(&:manifest),
          subcommands: subcommands.map(&:manifest)
        )
      end
    end

    # The single source of truth for help, man pages, completion and dispatch.
    class Registry
      attr_reader :program, :version, :description, :globals, :root

      # +builtins+ appends help, version, completion and __complete (see Builtins).
      def initialize(program:, version:, description:, globals:, commands:, builtins: true)
        @program = program
        @version = version
        @description = description
        @globals = globals
        extra = builtins ? Builtins.all(program:, version:, resolve: -> { self }) : []
        @root = Command.new(name: program, summary: description, subcommands: commands + extra)
      end

      # Follows +words+ down the command tree and returns [command, path], where +path+
      # is the list of consumed words; raises UsageError on the first unknown word.
      def resolve(words)
        words.reduce([root, []]) do |(command, path), word|
          nxt = command.find(word)
          raise UsageError.new(unknown_command(word, path), hint: run_hint(path)) unless nxt

          [nxt, [*path, word]]
        end
      end

      # The message for a word that names no command under +path+, with near misses.
      def unknown_command(word, path)
        message = "unknown command #{word.inspect} for #{[program, *path].join(' ').inspect}"
        with_guesses(message, word, resolve(path).first.visible_subcommands.flat_map(&:names))
      end

      # OptionParser attaches "Did you mean?" only on its abbreviation-completing path, which
      # require_exact disables, so suggestions for long switches come from the registry.
      def unknown_option(word, options)
        name = word.sub(/=.*/, '')
        message = "unknown flag: #{name}"
        return message unless name.start_with?('--')

        with_guesses(message, name, options.map { "--#{it.long}" })
      end

      # The hint for every usage error except an unknown command.
      def help_hint(path) = "See '#{[program, *path, '--help'].join(' ')}' for usage."

      # The hint for an unknown command, in kubectl's form.
      def run_hint(path) = "Run '#{[program, *path, '--help'].join(' ')}' for usage."

      # Plain data describing the whole command tree, for the man page generator.
      def manifest
        { program:, version:, description:, globals: globals.map(&:manifest),
          commands: root.subcommands.map(&:manifest) }
      end

      private

      def with_guesses(message, word, dictionary)
        guesses = Suggest.similar(word, dictionary)
        return message if guesses.empty?

        "#{message}\n\nDid you mean this?\n#{guesses.map { "\t#{it}" }.join("\n")}\n\n"
      end
    end

    # Cobra's rule for "Did you mean this?": Levenshtein distance <= 2 or a shared prefix.
    module Suggest
      DISTANCE = 2

      # The entries of +dictionary+ close enough to +word+ to be worth suggesting.
      def self.similar(word, dictionary)
        dictionary.select do |candidate|
          DidYouMean::Levenshtein.distance(word, candidate) <= DISTANCE ||
            candidate.start_with?(word) || word.start_with?(candidate)
        end
      end
    end
  end
end
