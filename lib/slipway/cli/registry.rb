# frozen_string_literal: true

module Slipway
  module CLI
    SECTION_ORDER = ['Basic Commands', 'Repository Commands', 'Settings Commands', 'Other Commands'].freeze

    # `long` has no dashes, and a nil `argument` makes a boolean flag. An `optional` option
    # takes its value only attached (--long=VALUE) and stores `implicit` when it is omitted.
    # `completer` is called with the words typed so far; see Completer for what it returns.
    Option = Data.define(:long, :short, :argument, :enum, :default, :description,
                         :repeatable, :required, :optional, :implicit, :completer) do
      def initialize(long:, description:, short: nil, argument: nil, enum: nil, default: nil,
                     repeatable: false, required: false, optional: false, implicit: nil, completer: nil)
        super
      end

      def key = long.tr('-', '_').to_sym

      def flag? = argument.nil?

      def switches = [short && "-#{short}", "--#{long}"].compact

      def switch_spec
        long_spec = if flag? then "--#{long}"
                    elsif optional then "--#{long}[=#{argument}]"
                    else "--#{long} #{argument}"
                    end
        [short && "-#{short}", long_spec].compact
      end

      def label
        text = switches.join(', ')
        return text if flag?

        optional ? "#{text}[=#{argument}]" : "#{text} #{argument}"
      end

      def description_parts
        parts = [description]
        parts << "One of: #{enum.join(', ')}." if enum
        parts << "(default #{default.inspect})" unless default.nil? || default == false
        parts << '(required)' if required
        parts
      end

      def accept(current, raw)
        return true if flag?
        return implicit if optional && raw.nil?
        return Array(current) << raw if repeatable

        raw
      end

      def candidates(given = []) = enum || completer&.call(given) || []
    end

    Positional = Data.define(:name, :required, :variadic, :enum, :completer) do
      def initialize(name:, required: true, variadic: false, enum: nil, completer: nil)
        super
      end

      def usage
        token = variadic ? "#{name}..." : name
        required ? token : "[#{token}]"
      end

      def candidates(given = []) = enum || completer&.call(given) || []
    end

    # `command` omits the program name; help and man pages prepend it.
    Example = Data.define(:comment, :command)

    # A titled list of terms and what each means, such as the columns or the result words a command
    # prints. `intro` is a paragraph printed above the terms.
    Glossary = Data.define(:title, :intro, :entries) do
      def initialize(title:, entries:, intro: nil) = super
    end

    # `handler` responds to call(context, args, opts). A `raw` command receives argv untouched,
    # with no option parsing, which is what the completion endpoint needs. `usage` replaces
    # the positional list in the Usage line when the accepted forms cannot be read off them.
    # `exit_statuses` maps each status to its meaning, for a command whose statuses differ from
    # the ones every command shares. `glossaries` are the Glossary sections help prints under the
    # description and the man page renders after the options.
    Command = Data.define(:name, :aliases, :summary, :description, :section, :examples, :positionals, :options,
                          :subcommands, :hidden, :raw, :handler, :usage, :exit_statuses, :glossaries) do
      def initialize(name:, summary:, description: nil, aliases: [], section: 'Available Commands', examples: [],
                     positionals: [], options: [], subcommands: [], hidden: false, raw: false, handler: nil,
                     usage: nil, exit_statuses: {}, glossaries: [])
        super(name:, summary:, description: description || summary, aliases:, section:, examples:,
              positionals:, options:, subcommands:, hidden:, raw:, handler:, usage:, exit_statuses:, glossaries:)
      end

      def group? = !subcommands.empty?

      def names = [name, *aliases]

      def find(word) = subcommands.find { it.names.include?(word) }

      def visible_subcommands = subcommands.reject(&:hidden)

      def sections
        visible_subcommands.group_by(&:section).sort_by.with_index do |(name, _), seen|
          [SECTION_ORDER.index(name) || SECTION_ORDER.size, seen]
        end
      end

      def positional_at(index) = positionals[index] || (positionals.last if positionals.last&.variadic)

      def min_args = positionals.count(&:required)

      def max_args = positionals.last&.variadic ? nil : positionals.size

      def usage_args
        return 'COMMAND' if group?

        usage || positionals.map(&:usage).join(' ')
      end
    end

    # The single source of truth for help, man pages, completion and dispatch.
    class Registry
      attr_reader :program, :version, :description, :globals, :root

      # `long_description` replaces `description` on the root help and man page. A Hash
      # `builtins` is passed on as options to the man builtin.
      def initialize(program:, version:, description:, globals:, commands:, long_description: nil, builtins: true)
        @program = program
        @version = version
        @description = description
        @globals = globals
        extra = builtins ? Builtins.all(program:, version:, resolve: -> { self }, **man_options(builtins)) : []
        @root = Command.new(name: program, summary: description, description: long_description,
                            subcommands: commands + extra)
      end

      def resolve(words)
        words.reduce([root, []]) do |(command, path), word|
          nxt = command.find(word)
          raise UsageError.new(unknown_command(word, path), hint: run_hint(path)) unless nxt

          [nxt, [*path, word]]
        end
      end

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

      # kubectl words the hint for an unknown command with Run and every other one with See.
      def help_hint(path) = "See '#{[program, *path, '--help'].join(' ')}' for usage."

      def run_hint(path) = "Run '#{[program, *path, '--help'].join(' ')}' for usage."

      private

      def man_options(builtins) = builtins == true ? {} : builtins

      def with_guesses(message, word, dictionary)
        guesses = Suggest.similar(word, dictionary)
        return message if guesses.empty?

        "#{message}\n\nDid you mean this?\n#{guesses.map { "\t#{it}" }.join("\n")}\n\n"
      end
    end

    # Cobra's rule for "Did you mean this?".
    module Suggest
      DISTANCE = 2

      def self.similar(word, dictionary)
        dictionary.select do |candidate|
          DidYouMean::Levenshtein.distance(word, candidate) <= DISTANCE ||
            candidate.start_with?(word) || word.start_with?(candidate)
        end
      end
    end
  end
end
