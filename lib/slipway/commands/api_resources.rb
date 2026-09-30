# frozen_string_literal: true

require_relative 'base'

module Slipway
  module Commands
    class APIResources < Base
      DESCRIPTION = "Print the supported resource types.\n\n" \
                    'Prints a table of the resource types slipway knows, sorted by name. A command accepts a type ' \
                    'by its NAME, its singular or one of its SHORTNAMES. Type words are case-insensitive. Use -o ' \
                    'name to print only the names.'
      COLUMNS = {
        'NAME' => 'The name of the type, in the plural.',
        'SHORTNAMES' => 'The aliases of the type, besides its singular.',
        'KIND' => 'The kind a manifest of the type declares.',
        'GROUPED' => 'Whether resources of the type live in a group, so that -n and -A scope them. kubectl\'s ' \
                     'NAMESPACED column says the same about namespaces.'
      }.freeze
      HEADERS = COLUMNS.keys.freeze
      GLOSSARIES = [
        CLI::Glossary.new(title: 'Columns',
                          intro: "A type without aliases reads #{Output::Table::NONE} in SHORTNAMES.",
                          entries: COLUMNS)
      ].freeze
      OUTPUT = Options::OUTPUT.with(enum: [Output::TABLE, Output::NAME])

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
          CLI::Example.new(comment: 'Print the names of the supported resource types', command: 'api-resources -o name')
        ]
      end
      private_class_method :examples

      def run(_runtime, context, _args, opts)
        types = Resources::KINDS.sort_by(&:plural)
        return types.each { context.puts(it.plural) } if opts[:output] == Output::NAME

        rows = types.map { [it.plural, it.aliases.join(','), it.title, it.namespaced?] }
        Output::Table.new(context, headers: HEADERS, show_headers: !opts[:no_headers]).print(rows)
      end
    end
  end
end
