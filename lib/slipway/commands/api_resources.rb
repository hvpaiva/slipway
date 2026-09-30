# frozen_string_literal: true

require_relative 'base'

module Slipway
  module Commands
    class APIResources < Base
      DESCRIPTION = "Print the supported resource types.\n\n" \
                    'Prints a table of the resource types slipway knows, sorted by name. A command accepts a type ' \
                    'by its NAME, its singular or one of its SHORTNAMES. Type words are case-insensitive. Use -o ' \
                    'wide to add the verbs that act on each type, and -o name to print only the names.'
      COLUMNS = {
        'NAME' => 'The name of the type, in the plural.',
        'SHORTNAMES' => 'The aliases of the type, besides its singular.',
        'KIND' => 'The kind a manifest of the type declares.',
        'GROUPED' => 'Whether resources of the type live in a group, so that -n and -A scope them. kubectl\'s ' \
                     'NAMESPACED column says the same about namespaces.',
        'VERBS' => 'The commands that act on resources of the type.'
      }.freeze
      WIDE_HEADERS = COLUMNS.keys.freeze
      HEADERS = (WIDE_HEADERS - ['VERBS']).freeze
      GLOSSARIES = [
        CLI::Glossary.new(title: 'Columns',
                          intro: 'Every type shows NAME, SHORTNAMES, KIND and GROUPED, and -o wide adds VERBS. A ' \
                                 "type without aliases reads #{Output::Table::NONE} in SHORTNAMES.",
                          entries: COLUMNS)
      ].freeze
      OUTPUT = Options::OUTPUT.with(enum: [Output::TABLE, Output::WIDE, Output::NAME])

      def self.command(factory)
        CLI::Command.new(
          name: 'api-resources', summary: 'Print the supported resource types', section: 'Other Commands',
          description: DESCRIPTION, examples:, glossaries: GLOSSARIES, options: [OUTPUT, Options::NO_HEADERS],
          handler: new(factory)
        )
      end

      def self.examples
        [
          CLI::Example.new(comment: 'Print the supported resource types', command: 'api-resources'),
          CLI::Example.new(comment: 'Print the supported resource types with more information',
                           command: 'api-resources -o wide'),
          CLI::Example.new(comment: 'Print the names of the supported resource types', command: 'api-resources -o name')
        ]
      end
      private_class_method :examples

      def run(_runtime, context, _args, opts)
        types = Resources::KINDS.sort_by(&:plural)
        case opts[:output]
        when Output::NAME then types.each { context.puts(it.plural) }
        when Output::WIDE
          verbs = verbs_by_kind
          table(context, opts, WIDE_HEADERS, types.map { [*row(it), verbs.fetch(it)] })
        else table(context, opts, HEADERS, types.map { row(it) })
        end
      end

      private

      def row(kind) = [kind.plural, kind.aliases.join(','), kind.title, kind.namespaced?]

      # The registry that holds this verb is built after it, so the verbs are built again from
      # VERBS to read what each one acts on.
      def verbs_by_kind
        commands = VERBS.map { it.command(@factory) }
        Resources::KINDS.to_h { |kind| [kind, commands.select { acts_on?(it, kind) }.map(&:name).sort.join(',')] }
      end

      # A group such as rollout acts on a kind when one of its subcommands does.
      def acts_on?(command, kind)
        return command.subcommands.any? { acts_on?(it, kind) } if command.group?

        command.handler.kinds.include?(kind)
      end

      def table(context, opts, headers, rows)
        Output::Table.new(context, headers:, show_headers: !opts[:no_headers]).print(rows)
      end
    end
  end
end
