# frozen_string_literal: true

require_relative 'base'
require_relative '../views'

module Slipway
  module Commands
    # `slipway describe TYPE [NAME...]`: every field of the selected resources, one block per
    # object, separated by a blank line.
    class Describe < Base
      DESCRIPTION = "Show details of a specific resource or group of resources.\n\n" \
                    'Print a detailed description of the selected resources, including the state of the ' \
                    'repository at the registered path. You may select a single object by name, all objects ' \
                    'of that type, or use a label selector.'

      def self.command(factory)
        CLI::Command.new(
          name: 'describe', summary: 'Show details of a specific resource or group of resources',
          section: 'Basic Commands', description: DESCRIPTION, examples:,
          positionals: [Options::TYPE, Options.name_positional(factory, variadic: true, required: false)],
          options: [Options::SELECTOR, Options::ALL_GROUPS],
          handler: new(factory)
        )
      end

      def self.examples
        [
          CLI::Example.new(comment: 'Describe a project', command: 'describe project hldr'),
          CLI::Example.new(comment: 'Describe every project in the work group', command: 'describe projects -n work'),
          CLI::Example.new(comment: 'Describe the projects labeled lang=rust',
                           command: 'describe projects -l lang=rust'),
          CLI::Example.new(comment: 'Describe a group', command: 'describe group work')
        ]
      end

      def run(runtime, context, args, opts)
        type, *names = args
        scope = scope(runtime, opts)
        kind = scope.kind(type)
        resources = scope.select(kind, names)
        return context.warn(scope.none_message(kind)) if resources.empty?

        blocks = kind.namespaced? ? projects(runtime, context, resources) : groups(runtime, resources)
        renderer = Output::Describe.new(context)
        context.print(blocks.map { renderer.render(it) }.join("\n"))
      end

      private

      def projects(runtime, context, resources)
        inspections = runtime.inspector.inspect_all(resources)
        runtime.inspector.warnings.each { context.warn("#{context.paint_err(:warning, 'warning:')} #{it}") }
        now = runtime.clock.call
        inspections.map { Views::Project.describe(it, now:) }
      end

      def groups(runtime, groups)
        now = runtime.clock.call
        groups.map { Views::Group.describe(it, count: runtime.store.project_count(it.name), now:) }
      end
    end
  end
end
