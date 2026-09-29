# frozen_string_literal: true

require_relative 'base'
require_relative '../labels'
require_relative '../store'

module Slipway
  module Commands
    class Create < Base
      DESCRIPTION = "Create a resource by name.\n\n" \
                    'A project registers the git repository at --path in the current group, which must ' \
                    'exist unless it is the default group. A group is created empty and holds the projects ' \
                    "you register with --group later.\n\n" \
                    "Use --dry-run=client to check the arguments without writing anything.\n\n" \
                    "#{Options::TYPES_SENTENCE}".freeze
      PATH_MISSING = 'required flag(s) "--path" not set'
      PATH_EMPTY = 'flag --path must not be empty'
      PATH_ON_GROUP = 'flag --path applies to projects only'

      PATH = CLI::Option.new(long: 'path', argument: 'DIR',
                             description: 'Directory of the git repository to register; required for projects. ' \
                                          'A relative directory is stored resolved against the current ' \
                                          'directory, a ~ path as written.')
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
                           command: "create project hldr --path '~/dev/hldr'"),
          CLI::Example.new(comment: 'Register a project in the work group with two labels',
                           command: "create project api --path '~/work/api' -n work --label lang=go --label tier=api"),
          CLI::Example.new(comment: 'Create a group with a description',
                           command: 'create group work --description "Projects for the day job"'),
          CLI::Example.new(comment: 'Check the arguments without writing the project',
                           command: "create project hldr --path '~/dev/hldr' --dry-run=client")
        ]
      end
      private_class_method :examples

      def run(runtime, context, args, opts)
        scope = scope(runtime, context, opts)
        kind, name = scope.target(args)
        resource = build(kind, name, scope.group, opts)
        dry_run = opts[:dry_run] == 'client'
        dry_run ? check(runtime.store, kind, resource) : runtime.store.create(resource)
        result_line(context, kind, name, 'created', :create_created, dry_run:)
      end

      private

      def build(kind, name, group, opts)
        labels = Labels.parse_pairs(opts[:label] || [])
        if kind.namespaced?
          Project.new(name:, group:, labels:, path: project_path(opts[:path]), description: opts[:description])
        else
          raise CLI::UsageError, PATH_ON_GROUP unless opts[:path].nil?

          Group.new(name:, labels:, description: opts[:description])
        end
      end

      # A manifest has no working directory, so a relative --path is resolved here, against
      # the directory the command was typed in; a ~ path stays portable as written.
      def project_path(path)
        raise CLI::UsageError, PATH_MISSING if path.nil?
        raise CLI::UsageError, PATH_EMPTY if path.strip.empty?
        return path if path.start_with?('~') || File.absolute_path?(path)

        File.absolute_path(path)
      end

      # What a real create would reject before writing.
      def check(store, kind, resource)
        return unless kind.namespaced?

        raise Store::NotFound.of(Resources::GROUPS, resource.group) unless store.group_available?(resource.group)
      end
    end
  end
end
