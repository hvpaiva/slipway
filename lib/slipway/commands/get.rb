# frozen_string_literal: true

require_relative 'base'
require_relative '../views'

module Slipway
  module Commands
    class Get < Base
      DESCRIPTION = "Display one or many resources.\n\n" \
                    'Prints a table of the most important information about the specified resources. ' \
                    'You can filter the list using a label selector and the --selector flag. Projects are ' \
                    "listed in the current group unless you pass --all-groups.\n\n" \
                    'Use -o wide to add the path, the head commit and the age of the last commit of each ' \
                    "project, and -o json or -o yaml for the full object with its status.\n\n" \
                    "#{Options::TYPES_SENTENCE}".freeze
      USAGE = '(TYPE [NAME...] | TYPE/NAME...)'

      def self.command(factory)
        CLI::Command.new(
          name: 'get', summary: 'Display one or many resources', section: 'Basic Commands',
          description: DESCRIPTION, examples:, usage: USAGE,
          positionals: [Options::TYPE, Options.name_positional(factory, variadic: true, required: false)],
          options: [Options::OUTPUT, Options::SELECTOR, Options::ALL_GROUPS, Options::NO_HEADERS,
                    Options::SHOW_LABELS],
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
          CLI::Example.new(comment: 'List every group', command: 'get groups')
        ]
      end
      private_class_method :examples

      def run(runtime, context, args, opts)
        scope = scope(runtime, context, opts)
        kind, names = scope.targets(args)
        scope.select(kind, names) do |resources|
          next scope.report_none(kind) if resources.empty?

          printer = Printer.new(runtime, context, opts, group_column: scope.all_groups?)
          printer.print(kind, printer.items(kind, resources), single: names.size == 1)
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
        # git answers.
        def items(kind, resources) = kind.namespaced? && !name? ? examine(resources) : resources

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
          columns = { wide: wide?, group: @group_column, labels: @opts[:show_labels] == true }
          now = @runtime.clock.call
          [Views::Project.headers(**columns), inspections.map { Views::Project.row(it, now:, **columns) },
           Views::Project::ROLES, @group_column ? 1 : 0]
        end

        def group_table(groups)
          now = @runtime.clock.call
          [Views::Group.headers(wide: wide?), groups.map { Views::Group.row(it, count: count(it), now:, wide: wide?) },
           nil, 0]
        end

        def examine(resources) = Base.examine(@runtime, @context, resources)

        def group_object(group) = Views::Group.object(group, count: count(group))

        def count(group) = @runtime.store.project_count(group.name)

        def wide? = @opts[:output] == Output::WIDE

        def name? = @opts[:output] == Output::NAME
      end

      private_constant :Printer
    end
  end
end
