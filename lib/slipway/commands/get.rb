# frozen_string_literal: true

require_relative 'base'
require_relative '../views'

module Slipway
  module Commands
    # `slipway get TYPE [NAME...]`: one line per resource as a table, wide table, json, yaml
    # or `type/name`. Projects are inspected first; groups carry their project count.
    class Get < Base
      DESCRIPTION = "Display one or many resources.\n\n" \
                    'Prints a table of the most important information about the specified resources. ' \
                    'You can filter the list using a label selector and the --selector flag. Projects are ' \
                    "listed in the current group unless you pass --all-groups.\n\n" \
                    'Use -o wide to add the path, the head commit and the age of the last commit of each ' \
                    "project, and -o json or -o yaml for the full object with its status.\n\n" \
                    "#{Options::TYPES_SENTENCE}".freeze
      USAGE = '(TYPE [NAME...] | TYPE/NAME...)'

      # The registry entry for `get`: the listing options, and NAME completed from the store.
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

      # Selects the resources, then renders them in the requested format; nothing is built
      # for a format that will not print it.
      def run(runtime, context, args, opts)
        scope = scope(runtime, context, opts)
        kind, names = scope.targets(args)
        scope.select(kind, names) do |resources|
          next scope.report_none(kind) if resources.empty?

          Printer.new(runtime, context, opts, group_column: scope.all_groups?)
                 .print(kind, resources, single: names.size == 1)
        end
      end

      # Renders one selection: `type/name` lines, json or yaml objects, or a table.
      class Printer
        def initialize(runtime, context, opts, group_column:)
          @runtime = runtime
          @context = context
          @opts = opts
          @group_column = group_column
        end

        # Prints +resources+ of +kind+; +single+ emits one object bare instead of a List.
        def print(kind, resources, single:)
          case @opts[:output]
          when Output::NAME then resources.each { @context.puts("#{kind.singular}/#{it.name}") }
          when *Output::Serializer::STRUCTURED then objects(kind, resources, single:)
          else table(kind, resources)
          end
        end

        private

        def objects(kind, resources, single:)
          items = if kind.namespaced? then examine(resources).map { Views::Project.object(it) }
                  else resources.map { Views::Group.object(it, count: count(it)) }
                  end
          @context.print(Output::Serializer.render(@opts[:output], items, single:))
        end

        def table(kind, resources)
          headers, rows, roles, offset = kind.namespaced? ? project_table(resources) : group_table(resources)
          Output::Table.new(@context, headers:, show_headers: !@opts[:no_headers], roles:, color_offset: offset)
                       .print(rows)
        end

        # The GROUP column -A prepends is left out of the color cycle, so the other columns
        # keep the colors they have without -A.
        def project_table(resources)
          columns = { wide: wide?, group: @group_column, labels: @opts[:show_labels] == true }
          inspections = examine(resources)
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

        def count(group) = @runtime.store.project_count(group.name)

        def wide? = @opts[:output] == Output::WIDE
      end

      private_constant :Printer
    end
  end
end
