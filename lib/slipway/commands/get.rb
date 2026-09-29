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
                    'project, and -o json or -o yaml for the full object with its status.'
      WIDE = 'wide'
      NAME = 'name'

      # One rendered listing: the table columns and rows, or the objects, of the selected resources.
      Listing = Data.define(:headers, :rows, :objects, :roles)

      def self.command(factory)
        CLI::Command.new(
          name: 'get', summary: 'Display one or many resources', section: 'Basic Commands',
          description: DESCRIPTION, examples:,
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

      def run(runtime, context, args, opts)
        type, *names = args
        scope = scope(runtime, opts)
        kind = scope.kind(type)
        resources = scope.select(kind, names)
        return context.warn(scope.none_message(kind)) if resources.empty?
        return print_names(context, kind, resources) if opts[:output] == NAME

        listing = if kind.namespaced? then projects(runtime, context, resources, columns(scope, opts))
                  else groups(runtime, resources, wide: opts[:output] == WIDE)
                  end
        render(context, listing, opts, single: names.size == 1)
      end

      private

      def print_names(context, kind, resources)
        resources.each { context.puts("#{kind.singular}/#{it.name}") }
      end

      # Which optional project columns the flags ask for.
      def columns(scope, opts)
        { wide: opts[:output] == WIDE, group: scope.all_groups?, labels: opts[:show_labels] == true }
      end

      def render(context, listing, opts, single:)
        format = opts[:output]
        if Output::Serializer::STRUCTURED.include?(format)
          context.print(Output::Serializer.render(format, listing.objects, single:))
        else
          Output::Table.new(context, headers: listing.headers, show_headers: !opts[:no_headers],
                                     roles: listing.roles).print(listing.rows)
        end
      end

      def projects(runtime, context, resources, columns)
        inspections = runtime.inspector.inspect_all(resources)
        runtime.inspector.warnings.each { context.warn("#{context.paint_err(:warning, 'warning:')} #{it}") }
        now = runtime.clock.call
        Listing.new(headers: Views::Project.headers(**columns),
                    rows: inspections.map { Views::Project.row(it, now:, **columns) },
                    objects: inspections.map { Views::Project.object(it) },
                    roles: Views::Project.roles)
      end

      def groups(runtime, groups, wide:)
        now = runtime.clock.call
        counts = groups.to_h { [it.name, runtime.store.project_count(it.name)] }
        Listing.new(headers: Views::Group.headers(wide:),
                    rows: groups.map { Views::Group.row(it, count: counts.fetch(it.name), now:, wide:) },
                    objects: groups.map { Views::Group.object(it, count: counts.fetch(it.name)) },
                    roles: nil)
      end
    end
  end
end
