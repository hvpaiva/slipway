# frozen_string_literal: true

require_relative 'base'
require_relative '../git/branch_name'
require_relative '../git/url'
require_relative '../labels'
require_relative '../store'

module Slipway
  module Commands
    class Create < Base
      DESCRIPTION = "Create a resource by name.\n\n" \
                    'A project registers the git repository at --path in the current group, which must ' \
                    'exist unless it is the default group. A group is created empty and holds the projects ' \
                    "you register with --group later.\n\n" \
                    'Use --dry-run=client to check the arguments without writing anything, and -o yaml with it ' \
                    "to print the manifest instead, ready for apply -f.\n\n" \
                    "#{Options::TYPES_SENTENCE}".freeze
      PATH_MISSING = 'required flag(s) "--path" not set'
      PATH_EMPTY = 'flag --path must not be empty'
      PROJECT_ONLY = 'flag --%s applies to projects only'
      PROJECT_FLAGS = %i[path remote branch].freeze

      # The resource as written, or as it would be on a dry run, and the word and role of its result line.
      Result = Data.define(:resource, :word, :role)

      PATH = CLI::Option.new(long: 'path', argument: 'DIR',
                             description: 'Directory of the git repository to register; required for projects. ' \
                                          'A relative directory is stored resolved against the current ' \
                                          'directory, a ~ path as written.')
      TEXT = CLI::Option.new(long: 'description', argument: 'TEXT',
                             description: 'A short description of the resource.')
      LABEL = CLI::Option.new(long: 'label', argument: 'KEY=VALUE', repeatable: true,
                              description: 'A label to set on the new resource; may be repeated.')
      REMOTE = CLI::Option.new(long: 'remote', argument: 'URL',
                               description: 'The URL the origin remote is expected to have, written to spec.remote. ' \
                                            'A URL that embeds credentials is refused; use a credential helper.')
      BRANCH = CLI::Option.new(long: 'branch', argument: 'NAME',
                               description: 'The branch the project is expected to have checked out, written to ' \
                                            'spec.branch.')
      OUTPUT = CLI::Option.new(long: 'output', short: 'o', argument: 'FORMAT',
                               enum: [*Output::Serializer::STRUCTURED, Output::NAME],
                               description: 'Output format; without it, each resource prints a result line such as ' \
                                            'project/hldr created.')

      def self.command(factory)
        CLI::Command.new(
          name: 'create', summary: 'Create a resource by name', section: 'Basic Commands',
          description: DESCRIPTION, examples:,
          positionals: [Options::TYPE, Options.name_positional(factory, variadic: false, required: true)],
          options: [PATH, TEXT, LABEL, REMOTE, BRANCH, Options::DRY_RUN, OUTPUT],
          handler: new(factory)
        )
      end

      def self.examples
        [
          CLI::Example.new(comment: 'Register the repository at ~/dev/hldr as a project in the current group',
                           command: "create project hldr --path '~/dev/hldr'"),
          CLI::Example.new(comment: 'Register a project in the work group with two labels',
                           command: "create project api --path '~/work/api' -n work --label lang=go --label tier=api"),
          CLI::Example.new(comment: 'Register a project with the remote and the branch it is expected to have',
                           command: "create project hldr --path '~/dev/hldr' " \
                                    '--remote git@github.com:hvpaiva/hldr.git --branch main'),
          CLI::Example.new(comment: 'Create a group with a description',
                           command: 'create group work --description "Projects for the day job"'),
          CLI::Example.new(comment: 'Check the arguments without writing the project',
                           command: "create project hldr --path '~/dev/hldr' --dry-run=client"),
          CLI::Example.new(comment: 'Print the manifest of a project without registering it',
                           command: "create project hldr --path '~/dev/hldr' --dry-run=client -o yaml")
        ]
      end
      private_class_method :examples

      def run(runtime, context, args, opts)
        scope = scope(runtime, context, opts)
        kind, name = scope.target(args)
        resource = build(kind, name, scope.group, opts)
        resource = dry_run?(opts) ? check(runtime.store, kind, resource) : runtime.store.create(resource)
        report(context, kind, [Result.new(resource, 'created', :create_created)], opts, single: true)
      end

      private

      def dry_run?(opts) = opts[:dry_run] == 'client'

      def report(context, kind, results, opts, single:)
        dry_run = dry_run?(opts)
        case opts[:output]
        when nil then results.each { result_line(context, kind, it.resource.name, it.word, it.role, dry_run:) }
        when Output::NAME then results.each { context.puts("#{kind.singular}/#{it.resource.name}") }
        else context.print(Output::Serializer.render(opts[:output], results.map { it.resource.to_manifest }, single:))
        end
      end

      def build(kind, name, group, opts)
        labels = Labels.parse_pairs(opts[:label] || [])
        return project(name, group, labels, opts) if kind.namespaced?

        flag = PROJECT_FLAGS.find { !opts[it].nil? }
        raise CLI::UsageError, format(PROJECT_ONLY, flag) if flag

        Group.new(name:, labels:, description: opts[:description])
      end

      def project(name, group, labels, opts)
        Project.new(name:, group:, labels:, path: project_path(opts[:path]), description: opts[:description],
                    remote: opts[:remote] && usage { Git::Url.validate!(opts[:remote], field: 'flag --remote') },
                    branch: opts[:branch] && usage { Git::BranchName.validate!(opts[:branch]) })
      end

      # A manifest has no working directory, so a relative --path is resolved here, against
      # the directory the command was typed in; a ~ path stays portable as written.
      def project_path(path)
        raise CLI::UsageError, PATH_MISSING if path.nil?
        raise CLI::UsageError, PATH_EMPTY if path.strip.empty?
        return path if path.start_with?('~') || File.absolute_path?(path)

        File.absolute_path(path)
      end

      # The checks a manifest's spec.remote and spec.branch pass, so a refusal reads the same; typed on
      # the command line, it is a usage error.
      def usage
        yield
      rescue Git::Url::Invalid, Git::BranchName::Invalid => e
        raise CLI::UsageError, e.message
      end

      # What a real create would reject before writing.
      def check(store, kind, resource)
        if kind.namespaced? && !store.group_available?(resource.group)
          raise Store::NotFound.of(Resources::GROUPS, resource.group)
        end

        resource
      end
    end
  end
end
