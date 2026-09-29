# frozen_string_literal: true

require_relative '../cli'
require_relative '../resources'
require_relative '../output'
require_relative 'scope'

module Slipway
  module Commands
    # The options and positionals several verbs share, worded as kubectl words them.
    module Options
      OUTPUT = CLI::Option.new(long: 'output', short: 'o', argument: 'FORMAT', enum: Output::Serializer::FORMATS,
                               default: 'table', description: 'Output format.')
      SELECTOR = CLI::Option.new(long: 'selector', short: 'l', argument: 'EXPR',
                                 description: "Selector (label query) to filter on, supports '=', '==', '!=', 'in', " \
                                              "'notin' (e.g. -l key1=value1,key2=value2,key3 in (value3)). " \
                                              'Matching objects must satisfy all of the specified label constraints.')
      ALL_GROUPS = CLI::Option.new(long: 'all-groups', short: 'A',
                                   description: 'If present, list the requested object(s) across all groups. ' \
                                                'The group in the current configuration is ignored even if ' \
                                                'specified with --group.')
      NO_HEADERS = CLI::Option.new(long: 'no-headers',
                                   description: "When using the default output format, don't print headers.")
      SHOW_LABELS = CLI::Option.new(long: 'show-labels',
                                    description: 'When printing, show all labels as the last column.')
      # Help appends the enum and the default after this sentence, in kubectl's "Must be" role.
      DRY_RUN = CLI::Option.new(long: 'dry-run', argument: 'STRATEGY', enum: %w[none client], default: 'none',
                                description: 'If client, only print what would change without writing anything.')

      # What completion says next to each resource type.
      TYPE_DESCRIPTIONS = {
        'projects' => 'Registered git repositories',
        'groups' => 'Namespaces that hold projects'
      }.freeze

      # The resource type word; unknown words are reported by Resources.resolve at run time.
      TYPE = CLI::Positional.new(name: 'TYPE', completer: ->(_given) { TYPE_DESCRIPTIONS })

      # The NAME positional, completed from the store through +factory+. The runtime is built
      # only when completion asks, with the process environment and no flags; any failure
      # along the way means no candidates rather than an error in the shell.
      def self.name_positional(factory, variadic: true, required: false)
        CLI::Positional.new(name: 'NAME', variadic:, required:, completer: ->(given) { names(factory, given) })
      end

      def self.names(factory, given)
        runtime = factory.call(CLI::Context.system, {})
        runtime.store.names(Resources.resolve(given.fetch(0)), group: nil)
      rescue StandardError
        []
      end
      private_class_method :names
    end

    # A verb's handler: builds the runtime through the factory it was given and hands the
    # call to +run+. Subclasses define `self.command(factory)` and `run`.
    class Base
      def initialize(factory)
        @factory = factory
      end

      def call(context, args, opts)
        runtime = @factory.call(context, opts)
        run(runtime, context, args, opts)
      end

      protected

      def scope(runtime, opts) = Scope.new(runtime, opts)

      # Prints kubectl's result line, `project/hldr created`, with the verb painted in +role+
      # and ` (dry run)` appended when nothing was written.
      def result_line(context, kind, name, verb_word, role, dry_run: false)
        line = "#{kind.singular}/#{name} #{context.paint(role, verb_word)}"
        line = "#{line} #{context.paint(:dry_run, '(dry run)')}" if dry_run
        context.puts(line)
      end
    end
  end
end
