# frozen_string_literal: true

require_relative 'base'
require_relative '../manifest'
require_relative '../store'

module Slipway
  module Commands
    class Apply < Base
      # Raised once, after every document that could be applied was.
      class Failed < Error; end

      DESCRIPTION = "Apply a configuration to a resource by file name or stdin.\n\n" \
                    'The resource name must be specified in the manifest. A resource is created when it does ' \
                    'not exist yet, configured when its manifest differs from the one stored, and reported ' \
                    'unchanged otherwise. A directory applies every *.yaml and *.yml file it holds, sorted by ' \
                    'name and without descending into subdirectories. A project manifest without ' \
                    "metadata.group lands in the current group.\n\n" \
                    'YAML is accepted, with several documents per file, and a document of kind List stands ' \
                    'for each of its items. Documents are applied in order, so a group may be created by the ' \
                    'document before the projects that use it.'
      STDIN_FLAG = '-'
      NO_OBJECTS = 'no objects passed to apply'

      FILENAME = CLI::Option.new(long: 'filename', short: 'f', argument: 'FILE', repeatable: true, required: true,
                                 completer: ->(_given, _current) { CLI::Completer::FILES },
                                 summary: 'The file that contains the manifests to apply',
                                 description: 'The file that contains the manifests to apply; may be repeated. ' \
                                              "A directory reads its *.yaml and *.yml files, '-' reads stdin.")

      def self.command(factory)
        CLI::Command.new(
          name: 'apply', summary: 'Apply a configuration to a resource by file name or stdin',
          section: 'Basic Commands', description: DESCRIPTION, examples:,
          options: [FILENAME, Options::DRY_RUN],
          handler: new(factory)
        )
      end

      def self.examples
        [
          CLI::Example.new(comment: 'Apply the configuration in hldr.yaml to a project',
                           command: 'apply -f hldr.yaml'),
          CLI::Example.new(comment: 'Apply every manifest in a directory', command: 'apply -f ./projects'),
          CLI::Example.new(comment: 'Apply the YAML passed into stdin', command: 'apply -f - < hldr.yaml'),
          CLI::Example.new(comment: 'Show what would change without writing anything',
                           command: 'apply -f hldr.yaml --dry-run')
        ]
      end
      private_class_method :examples

      def kinds = Resources::KINDS

      def run(runtime, context, _args, opts)
        dry_run = opts[:dry_run] == true
        session = Session.new(runtime.store, default_group: scope(runtime, context, opts).group, dry_run:)
        opts[:filename].each do |file|
          session.apply(file) { |kind, name, word, role| result_line(context, kind, name, word, role, dry_run:) }
        end
        finish(session)
      end

      private

      def finish(session)
        raise Failed, NO_OBJECTS if session.problems.empty? && session.applied.zero?
        raise Failed.new(problems: session.problems) unless session.problems.empty?
      end

      # A failed document is remembered in `problems` so the rest still run.
      class Session
        STDIN_SOURCE = 'STDIN'
        EXTENSIONS = %w[.yaml .yml].freeze

        attr_reader :problems, :applied

        def initialize(store, default_group:, dry_run:)
          @store = store
          @default_group = default_group
          @dry_run = dry_run
          @problems = []
          @applied = 0
          @dry_run_groups = []
        end

        def apply(name, &)
          read(name).each { |source, text| apply_stream(source, text, &) }
        rescue Error => e
          @problems << e.message
        end

        private

        # The Context carries no input stream, so `-` reads the process's standard input.
        def read(name)
          return [[STDIN_SOURCE, $stdin.read]] if name == STDIN_FLAG
          return directory(name) if File.directory?(name)

          [[name, File.read(name)]]
        rescue Errno::ENOENT
          raise Error, "#{name}: no such file"
        rescue SystemCallError => e
          raise Error.from_system_call(e, name)
        end

        def directory(name)
          files = Dir.children(name).select { EXTENSIONS.include?(File.extname(it)) }.sort
          files = files.map { File.join(name, it) }.select { File.file?(it) }
          raise Error, "#{name}: no .yaml or .yml files" if files.empty?

          files.map { [it, File.read(it)] }
        end

        def apply_stream(source, text, &)
          documents = Manifest.load_objects(text, source:)
          documents.each_with_index do |document, index|
            label = documents.size > 1 ? "#{source}:#{index + 1}" : source
            collect(label) { apply_resource(Manifest.parse(document, source: label, default_group: @default_group), &) }
          end
        end

        # A problem the manifest reader found already names its source; a store error is
        # prefixed with it so every collected line reads `<source>: <problem>`.
        def collect(source)
          yield
        rescue Manifest::Invalid => e
          @problems << e.message
        rescue Error => e
          @problems << "#{source}: #{e.message}"
        end

        def apply_resource(resource)
          kind = Resources.of(resource)
          group = kind.namespaced? ? resource.group : nil
          existing = @store.find(kind, resource.name, group:) if @store.exist?(kind, resource.name, group:)
          word, role = existing ? update(existing, resource) : create(kind, resource)
          @applied += 1
          yield kind, resource.name, word, role
        end

        # The stored creationTimestamp is kept; anything else that differs is a change.
        def update(existing, incoming)
          incoming = incoming.with(created_at: existing.created_at)
          return ['unchanged', :apply_unchanged] if Manifest.dump(existing) == Manifest.dump(incoming)

          @store.save(incoming) unless @dry_run
          ['configured', :apply_configured]
        end

        def create(kind, resource)
          if @dry_run
            check_group(resource) if kind.namespaced?
            @dry_run_groups << resource.name unless kind.namespaced?
          else
            @store.create(resource)
          end
          ['created', :apply_created]
        end

        # A dry run writes nothing, so a group created earlier in the same run is remembered
        # here for the projects that follow it.
        def check_group(project)
          group = project.group
          return if @dry_run_groups.include?(group) || @store.group_available?(group)

          raise Store::NotFound.of(Resources::GROUPS, group)
        end
      end

      private_constant :Session
    end
  end
end
