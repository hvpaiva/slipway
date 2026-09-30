# frozen_string_literal: true

require_relative 'base'
require_relative '../views'

module Slipway
  module Commands
    class Describe < Base
      DESCRIPTION = "Show details of one or many resources.\n\n" \
                    'Print a detailed description of the selected resources, including the state of the ' \
                    'repository at the registered path. You may select a single object by name, all objects ' \
                    "of that type, or use a label selector.\n\n" \
                    "#{Options::TYPES_SENTENCE}".freeze

      def self.command(factory)
        CLI::Command.new(
          name: 'describe', summary: 'Show details of one or many resources',
          section: 'Basic Commands', description: DESCRIPTION, examples:, usage: Get::USAGE,
          positionals: [Options::TYPE, Options.name_positional(factory, variadic: true, required: false)],
          options: [Options::SELECTOR, Options::FIELD_SELECTOR, Options::ALL_GROUPS],
          handler: new(factory)
        )
      end

      def self.examples
        [
          CLI::Example.new(comment: 'Describe a project', command: 'describe project hldr'),
          CLI::Example.new(comment: 'Describe every project in the work group', command: 'describe projects -n work'),
          CLI::Example.new(comment: 'Describe the projects labeled lang=rust',
                           command: 'describe projects -l lang=rust'),
          CLI::Example.new(comment: 'Describe the projects on the main branch',
                           command: 'describe projects --field-selector status.branch=main'),
          CLI::Example.new(comment: 'Describe a group', command: 'describe group work')
        ]
      end
      private_class_method :examples

      def run(runtime, context, args, opts)
        scope = scope(runtime, context, opts)
        kind, names = scope.targets(args)
        fields = scope.field_selector(kind, names)
        scope.select(kind, names) do |resources|
          blocks = kind.namespaced? ? projects(runtime, context, resources, fields) : groups(runtime, resources, fields)
          next scope.report_none(kind) if blocks.empty?

          renderer = Output::Describe.new(context)
          context.print(blocks.map { renderer.render(it) }.join("\n"))
        end
      end

      private

      def projects(runtime, context, resources, fields)
        inspections = fields.filter(Base.examine(runtime, context, resources)) { Views::Project.object(it) }
        now = runtime.clock.call
        inspections.map { Views::Project.describe(it, now:) }
      end

      def groups(runtime, groups, fields)
        now = runtime.clock.call
        counted = groups.map { [it, runtime.store.project_count(it.name)] }
        fields.filter(counted) { |group, count| Views::Group.object(group, count:) }
              .map { |group, count| Views::Group.describe(group, count:, now:) }
      end
    end
  end
end
