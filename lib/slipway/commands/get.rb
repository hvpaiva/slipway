# frozen_string_literal: true

require_relative 'base'
require_relative '../views'

module Slipway
  module Commands
    class Get < Base
      DESCRIPTION = "Display one or many resources.\n\n" \
                    'Prints a table of the most important information about the specified resources. ' \
                    'You can filter the list using a label selector and the --selector flag, or a field ' \
                    'selector and the --field-selector flag. Projects are listed in the current group unless ' \
                    "you pass --all-groups.\n\n" \
                    'Use -o wide to add the path, the head commit, the age of the last commit and the drift of ' \
                    'each project: the ways its repository differs from its manifest and what keeps sync from ' \
                    "converging it. Use -o json or -o yaml for the full object with its status.\n\n" \
                    "#{Options::TYPES_SENTENCE}".freeze
      USAGE = '(<TYPE> [NAME]... | <TYPE/NAME>...)'
      COLUMNS = {
        'GROUP' => 'The group of the project.',
        'NAME' => 'The name of the resource.',
        'BRANCH' => "The checked-out branch, or #{Views::Project::DETACHED} when HEAD points at a commit.",
        'STATUS' => 'One word for the state of the repository, from the list below.',
        'FETCHED' => 'Time since the repository was last fetched, by slipway or by git itself and from any of its ' \
                     "worktrees. #{Views::Project::NEVER} means git answered and no fetch is on record, which " \
                     'includes a last fetch that failed.',
        'AGE' => 'Time since the resource was registered, in kubectl\'s units (3s, 4m12s, 11h, 2y319d).',
        'PATH' => 'The registered path, as the manifest writes it.',
        'HEAD' => 'The abbreviated id of the checked-out commit.',
        'LAST-COMMIT' => 'The age of the checked-out commit.',
        'DRIFT' => 'The ways the repository differs from its manifest and the blocker that keeps sync from ' \
                   'fast-forwarding it, as slipway diff names them.',
        'PROJECTS' => 'The number of projects in the group.',
        'DESCRIPTION' => 'The description of the group.',
        'LABELS' => 'The labels, as key=value pairs.'
      }.freeze
      STATUS_WORDS = CLI::Glossary.new(title: 'Status Words',
                                       intro: 'STATUS is the first of these words that holds, in this order.',
                                       entries: State::MEANINGS)
      GLOSSARIES = [
        CLI::Glossary.new(
          title: 'Columns',
          intro: 'Projects show NAME, BRANCH, STATUS, FETCHED and AGE; --all-groups adds GROUP in front, -o wide ' \
                 'adds PATH, HEAD, LAST-COMMIT and DRIFT, and --show-labels adds LABELS. Groups show NAME, ' \
                 'PROJECTS and AGE, and -o wide adds DESCRIPTION. A cell slipway has no value for reads ' \
                 "#{Output::Table::NONE}, as every cell from git does when git cannot read the repository.",
          entries: COLUMNS
        ),
        STATUS_WORDS
      ].freeze

      def self.command(factory)
        CLI::Command.new(
          name: 'get', summary: 'Display one or many resources', section: 'Basic Commands',
          description: DESCRIPTION, examples:, usage: USAGE, glossaries: GLOSSARIES,
          positionals: [Options::TYPE, Options.name_positional(factory, variadic: true, required: false)],
          options: [Options::OUTPUT, Options::SELECTOR, Options::FIELD_SELECTOR, Options::ALL_GROUPS,
                    Options::NO_HEADERS, Options::SHOW_LABELS],
          handler: new(factory)
        )
      end

      def self.examples
        [
          CLI::Example.new(comment: 'List all projects in the current group', command: 'get projects'),
          CLI::Example.new(comment: 'List all projects in every group, with the path and last commit',
                           command: 'get projects -A -o wide'),
          CLI::Example.new(comment: 'List a single project in YAML output format',
                           command: 'get project hldr -o yaml'),
          CLI::Example.new(comment: 'List the projects labeled lang=rust', command: 'get projects -l lang=rust'),
          CLI::Example.new(comment: 'List the projects in every group that are not clean',
                           command: 'get projects -A --field-selector status.state!=Clean'),
          CLI::Example.new(comment: 'List the projects no fetch has reached',
                           command: 'get projects --field-selector status.lastFetch=never'),
          CLI::Example.new(comment: 'List every group', command: 'get groups')
        ]
      end
      private_class_method :examples

      def kinds = Resources::KINDS

      def run(runtime, context, args, opts)
        scope = scope(runtime, context, opts)
        kind, names = scope.targets(args)
        fields = scope.field_selector(kind, names)
        scope.select(kind, names) do |resources|
          printer = Printer.new(runtime, context, opts, group_column: scope.all_groups?)
          items = printer.items(kind, resources, fields)
          next scope.report_none(kind) if items.empty?

          printer.print(kind, items, single: names.size == 1)
        end
      end

      class Printer
        def initialize(runtime, context, opts, group_column:)
          @runtime = runtime
          @context = context
          @opts = opts
          @group_column = group_column
        end

        # Projects come back examined for every format but name, the one that shows nothing
        # git answers. A field selector reads what git answered, so with one even -o name
        # examines them.
        def items(kind, resources, fields)
          return fields.filter(resources) { group_object(it) } unless kind.namespaced?
          return resources if name? && fields.empty?

          inspections = fields.filter(examine(resources)) { Views::Project.object(it) }
          name? ? inspections.map(&:project) : inspections
        end

        def print(kind, items, single:)
          case @opts[:output]
          when Output::NAME then items.each { @context.puts("#{kind.singular}/#{it.name}") }
          when *Output::Serializer::STRUCTURED then objects(kind, items, single:)
          else table(kind, items)
          end
        end

        private

        def objects(kind, items, single:)
          objects = items.map { kind.namespaced? ? Views::Project.object(it) : group_object(it) }
          @context.print(Output::Serializer.render(@opts[:output], objects, single:))
        end

        def table(kind, items)
          headers, rows, roles, offset = kind.namespaced? ? project_table(items) : group_table(items)
          Output::Table.new(@context, headers:, show_headers: !@opts[:no_headers], roles:, color_offset: offset)
                       .print(rows)
        end

        # The GROUP column -A prepends is left out of the color cycle, so the other columns
        # keep the colors they have without -A.
        def project_table(inspections)
          columns = { wide: wide?, group: @group_column, labels: labels? }
          now = @runtime.clock.call
          [Views::Project.headers(**columns), inspections.map { Views::Project.row(it, now:, **columns) },
           Views::Project::ROLES, @group_column ? 1 : 0]
        end

        def group_table(groups)
          columns = { wide: wide?, labels: labels? }
          now = @runtime.clock.call
          [Views::Group.headers(**columns), groups.map { Views::Group.row(it, count: count(it), now:, **columns) },
           nil, 0]
        end

        def examine(resources) = Base.examine(@runtime, @context, resources)

        def group_object(group) = Views::Group.object(group, count: count(group))

        def count(group) = @runtime.store.project_count(group.name)

        def wide? = @opts[:output] == Output::WIDE

        def labels? = @opts[:show_labels] == true

        def name? = @opts[:output] == Output::NAME
      end

      private_constant :Printer
    end
  end
end
