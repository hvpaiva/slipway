# frozen_string_literal: true

require_relative 'base'
require_relative 'from_dir'
require_relative '../git/branch_name'
require_relative '../git/url'
require_relative '../labels'
require_relative '../scanner'
require_relative '../store'

module Slipway
  module Commands
    class Create < Base
      DESCRIPTION = "Create a resource by name.\n\n" \
                    'A project registers the git repository at --path in the current group, which must ' \
                    'exist unless it is the default group. A group is created empty and holds the projects ' \
                    "you register with --group later.\n\n" \
                    'With --from-dir DIR in place of NAME, create project registers every git repository at DIR ' \
                    'or under it, down to --depth levels. Each project is named after its directory, lowercased ' \
                    'with each run of characters other than ASCII letters, digits and dashes made one dash, and ' \
                    'records its path and the URL of its origin without any credentials; the checked-out branch ' \
                    'is not recorded. A path the group already holds is reported unchanged, so running it again ' \
                    "adds only new clones.\n\n" \
                    'Use --dry-run to check the arguments without writing anything, and -o yaml with it ' \
                    "to print the manifest instead, ready for apply -f.\n\n" \
                    "#{Options::TYPES_SENTENCE}".freeze
      PATH_MISSING = 'required flag(s) "--path" not set'
      PATH_EMPTY = 'flag --path must not be empty'
      PROJECT_ONLY = 'flag --%s applies to projects only'
      PROJECT_FLAGS = %i[path remote branch].freeze
      EITHER = 'give either NAME or --from-dir, not both'
      NOT_WITH_FROM_DIR = 'flag --%s cannot be used with --from-dir'
      FROM_DIR_EXCLUSIVE = %i[path description remote branch].freeze
      FROM_DIR_EMPTY = 'flag --from-dir must not be empty'
      DEPTHS = 1..Scanner::MAX_DEPTH
      DEPTH_INVALID = "invalid argument %p for --depth: must be an integer from #{DEPTHS.min} to #{DEPTHS.max}".freeze
      DEPTH_WITHOUT_FROM_DIR = 'flag --depth requires --from-dir'
      USAGE = '(TYPE NAME | project --from-dir DIR)'

      # The resource as written, or as it would be on a dry run, and the word and role of its result line.
      Result = Data.define(:resource, :word, :role)

      PATH = CLI::Option.new(long: 'path', argument: 'DIR',
                             completer: ->(_given, _current) { CLI::Completer::FILES },
                             description: 'Directory of the git repository to register; required for a project ' \
                                          'given by NAME. ' \
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
      FROM_DIR = CLI::Option.new(long: 'from-dir', argument: 'DIR',
                                 completer: ->(_given, _current) { CLI::Completer::FILES },
                                 description: 'Register every git repository at or under DIR as a project, in ' \
                                              'place of NAME.')
      # No option default: one would hide whether --depth was typed without --from-dir.
      DEPTH = CLI::Option.new(long: 'depth', argument: 'N',
                              description: "How many directory levels under --from-dir to search, from #{DEPTHS.min} " \
                                           "to #{DEPTHS.max}. The search stops at a repository and never follows " \
                                           "a symbolic link under --from-dir. (default #{Scanner::DEFAULT_DEPTH})")
      OUTPUT = CLI::Option.new(long: 'output', short: 'o', argument: 'FORMAT',
                               enum: [*Output::Serializer::STRUCTURED, Output::NAME],
                               description: 'Output format; without it, each resource prints a result line such as ' \
                                            'project/hldr created.')

      def self.command(factory)
        CLI::Command.new(
          name: 'create', summary: 'Create a resource by name', section: 'Basic Commands',
          description: DESCRIPTION, examples:, usage: USAGE,
          positionals: [Options::TYPE, Options.name_positional(factory, variadic: false, required: false)],
          options: [PATH, TEXT, LABEL, REMOTE, BRANCH, FROM_DIR, DEPTH, Options::DRY_RUN, OUTPUT],
          handler: new(factory)
        )
      end

      def self.examples = named_examples + directory_examples

      def self.named_examples
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
                           command: "create project hldr --path '~/dev/hldr' --dry-run"),
          CLI::Example.new(comment: 'Print the manifest of a project without registering it',
                           command: "create project hldr --path '~/dev/hldr' --dry-run -o yaml")
        ]
      end

      def self.directory_examples
        [
          CLI::Example.new(comment: 'Register every repository in ~/dev/personal in the personal group',
                           command: 'create project --from-dir ~/dev/personal -n personal'),
          CLI::Example.new(comment: 'Write the manifests of the repositories two levels under ~/work to a file',
                           command: 'create project --from-dir ~/work --depth 2 --dry-run -o yaml > work.yaml')
        ]
      end
      private_class_method :examples, :named_examples, :directory_examples

      def kinds = Resources::KINDS

      def run(runtime, context, args, opts)
        scope = scope(runtime, context, opts)
        kind, names = scope.targets(args)
        return register_directory(runtime, context, scope, opts) if from_dir?(kind, names, opts)
        raise CLI::UsageError, DEPTH_WITHOUT_FROM_DIR unless opts[:depth].nil?

        _, name = scope.target(args)
        resource = build(kind, name, scope.group, opts)
        resource = dry_run?(opts) ? check(runtime.store, kind, resource) : runtime.store.create(resource)
        report(context, kind, [Result.new(resource, 'created', :create_created)], opts, single: true)
      end

      private

      def dry_run?(opts) = opts[:dry_run] == true

      # NAME and --from-dir are the two ways to say which project to register; a group has only NAME.
      def from_dir?(kind, names, opts)
        return false if opts[:from_dir].nil?
        raise CLI::UsageError, format(PROJECT_ONLY, 'from-dir') unless kind.namespaced?
        raise CLI::UsageError, EITHER unless names.empty?

        true
      end

      def register_directory(runtime, context, scope, opts)
        check_directory_flags(opts)
        labels = Labels.parse_pairs(opts[:label] || [])
        registrar = FromDir.new(runtime, context, group: scope.group, labels:, dry_run: dry_run?(opts))
        entries = registrar.register(opts[:from_dir], depth: depth(opts[:depth] || Scanner::DEFAULT_DEPTH))
        report(context, Resources::PROJECTS, entries.map { result_of(it) }, opts, single: false)
        raise Error.new(problems: registrar.problems) unless registrar.problems.empty?
      end

      def check_directory_flags(opts)
        flag = FROM_DIR_EXCLUSIVE.find { !opts[it].nil? }
        raise CLI::UsageError, format(NOT_WITH_FROM_DIR, flag) if flag
        raise CLI::UsageError, FROM_DIR_EMPTY if opts[:from_dir].strip.empty?
      end

      def depth(value)
        depth = Integer(value.to_s, 10, exception: false)
        DEPTHS.cover?(depth) ? depth : raise(CLI::UsageError, format(DEPTH_INVALID, value.to_s))
      end

      def result_of(entry)
        if entry.created then Result.new(entry.project, 'created', :create_created)
        else Result.new(entry.project, 'unchanged', :apply_unchanged)
        end
      end

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
