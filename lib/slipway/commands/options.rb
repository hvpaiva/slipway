# frozen_string_literal: true

require_relative '../cli'
require_relative '../resources'
require_relative '../output'
require_relative '../views'

module Slipway
  module Commands
    module Options
      OUTPUT = CLI::Option.new(long: 'output', short: 'o', argument: 'FORMAT', enum: Output::FORMATS,
                               default: Output::TABLE, description: 'Output format.')
      SELECTOR = CLI::Option.new(long: 'selector', short: 'l', argument: 'EXPR',
                                 description: "Selector (label query) to filter on, supports '=', '==', '!=', 'in', " \
                                              "'notin' (e.g. -l key1=value1,key2=value2,key3 in (value3)). " \
                                              'Matching objects must satisfy all of the specified label constraints.')
      FIELD_SELECTOR = CLI::Option.new(long: 'field-selector', argument: 'EXPR',
                                       description: "Selector (field query) to filter on, supports '=', '==', and " \
                                                    "'!=' (e.g. --field-selector key1=value1,key2=value2). Projects " \
                                                    "support #{Views::Project::FIELDS.keys.join(', ')}; groups " \
                                                    "support #{Views::Group::FIELDS.keys.join(', ')}. Values " \
                                                    'compare exactly, case included, with the object -o json ' \
                                                    'prints: spec.path as registered, status.lastFetch as an RFC ' \
                                                    '3339 time. A field the object leaves out compares as the ' \
                                                    'empty value, except status.lastFetch, which compares as never. ' \
                                                    'A backslash escapes a backslash, a comma or an equals sign in ' \
                                                    'a value.')
      ALL_GROUPS = CLI::Option.new(long: 'all-groups', short: 'A',
                                   description: 'If present, list the requested object(s) across all groups. ' \
                                                'The group in the current configuration is ignored even if ' \
                                                'specified with --group.')
      NO_HEADERS = CLI::Option.new(long: 'no-headers',
                                   description: "When using the default output format, don't print headers.")
      SHOW_LABELS = CLI::Option.new(long: 'show-labels',
                                    description: 'When printing, show all labels as the last column.')
      DRY_RUN = CLI::Option.new(long: 'dry-run', description: 'Print what would change and write nothing.')

      TYPE_DESCRIPTIONS = {
        'projects' => 'Registered git repositories',
        'groups' => 'Namespaces that hold projects'
      }.freeze

      TYPES = Resources::KINDS.map { "#{it.plural} (#{[it.singular, *it.aliases].join(', ')})" }.join(' and ')
      TYPES_SENTENCE = "Resource types: #{TYPES}. Type words are case-insensitive.".freeze

      # Unknown words are reported by Resources.resolve at run time.
      TYPE = CLI::Positional.new(name: 'TYPE', completer: ->(_given) { TYPE_DESCRIPTIONS })

      def self.name_positional(factory, variadic: true, required: false)
        CLI::Positional.new(name: 'NAME', variadic:, required:, completer: ->(given) { names(factory, given) })
      end

      # No TYPE word comes first, so completion always offers project names.
      def self.project_positional(factory, variadic: true, required: false)
        CLI::Positional.new(name: 'NAME', variadic:, required:,
                            completer: ->(_given) { names(factory, [Resources::PROJECTS.plural]) })
      end

      def self.group_completer(factory) = ->(_given) { names(factory, [Resources::GROUPS.plural]) }

      # Runs during shell completion, with the process environment and no flags: any failure
      # means no candidates rather than an error in the shell.
      def self.names(factory, given)
        runtime = factory.call(CLI::Context.system, {})
        runtime.store.names(Resources.resolve(given.fetch(0)), group: nil)
      rescue StandardError
        []
      end
      private_class_method :names
    end
  end
end
