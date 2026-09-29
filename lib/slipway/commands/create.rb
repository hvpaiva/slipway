# frozen_string_literal: true

require_relative 'base'
require_relative '../labels'
require_relative '../names'
require_relative '../store'

module Slipway
  module Commands
    # `slipway create TYPE NAME`: registers a project or a group from command-line flags.
    class Create < Base
      DESCRIPTION = "Create a resource by name.\n\n" \
                    'A project registers the git repository at --path in the current group, which must ' \
                    'exist unless it is the default group. A group is created empty and holds the projects ' \
                    "you register with --group later.\n\n" \
                    'Use --dry-run=client to check the arguments without writing anything.'
      PATH_MISSING = 'required flag(s) "--path" not set'
      PATH_ON_GROUP = 'flag --path applies to projects only'

      PATH = CLI::Option.new(long: 'path', argument: 'DIR',
                             description: 'Directory of the git repository to register; ' \
                                          'required for projects and stored as written.')
      TEXT = CLI::Option.new(long: 'description', argument: 'TEXT',
                             description: 'A short description of the resource.')
      LABEL = CLI::Option.new(long: 'label', argument: 'KEY=VALUE', repeatable: true,
                              description: 'A label to set on the new resource; may be repeated.')

      def self.command(factory)
        CLI::Command.new(
          name: 'create', summary: 'Create a resource by name', section: 'Basic Commands',
          description: DESCRIPTION, examples:,
          positionals: [Options::TYPE, Options.name_positional(factory, variadic: false, required: true)],
          options: [PATH, TEXT, LABEL, Options::DRY_RUN],
          handler: new(factory)
        )
      end

      def self.examples
        [
          CLI::Example.new(comment: 'Register the repository at ~/dev/hldr as a project in the current group',
                           command: 'create project hldr --path ~/dev/hldr'),
          CLI::Example.new(comment: 'Register a project in the work group with two labels',
                           command: 'create project api --path ~/work/api -n work --label lang=go --label tier=api'),
          CLI::Example.new(comment: 'Create a group with a description',
                           command: 'create group work --description "Projects for the day job"'),
          CLI::Example.new(comment: 'Check the arguments without writing the project',
                           command: 'create project hldr --path ~/dev/hldr --dry-run=client')
        ]
      end

      def run(runtime, context, args, opts)
        type, name = args
        scope = scope(runtime, opts)
        kind = scope.kind(type)
        resource = build(kind, name, scope.group, opts)
        dry_run = opts[:dry_run] == 'client'
        dry_run ? check(runtime.store, kind, resource) : runtime.store.create(resource)
        result_line(context, kind, name, 'created', :create_created, dry_run:)
      end

      private

      def build(kind, name, group, opts)
        labels = Labels.parse_pairs(opts[:label] || [])
        if kind.namespaced?
          raise CLI::UsageError, PATH_MISSING if opts[:path].nil?

          Project.new(name:, group:, labels:, path: opts[:path], description: opts[:description])
        else
          raise CLI::UsageError, PATH_ON_GROUP unless opts[:path].nil?

          Group.new(name:, labels:, description: opts[:description])
        end
      end

      # What a real create would reject before writing: the names and, for a project, its
      # group. The default group is created on demand, so it counts as present.
      def check(store, kind, resource)
        Names.validate!(resource.name, what: "#{kind.singular} name")
        return unless kind.namespaced?

        group = Names.validate!(resource.group, what: 'group name')
        return if group == Store::DEFAULT_GROUP || store.exist?(Resources.resolve('groups'), group, group: nil)

        raise Store::NotFound, "group #{group.inspect} not found"
      end
    end
  end
end
