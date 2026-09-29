# frozen_string_literal: true

require_relative '../error'
require_relative '../git/errors'
require_relative '../git/url'
require_relative '../names'
require_relative '../output'
require_relative '../paths'
require_relative '../resources'
require_relative '../scanner'
require_relative '../store'

module Slipway
  module Commands
    # Registers the repositories Scanner finds for create project --from-dir. Each is keyed by
    # its path within the group, so a second run over the same directory adds only new clones.
    class FromDir
      # +created+ is false for a path the group already held; +project+ is then the stored one.
      Entry = Data.define(:project, :created)

      NONE_FOUND = 'no git repositories found under %s to depth %d'
      TAKEN = 'project %p already exists at %s'
      ORIGIN_FIELD = 'origin'
      NOT_UTF8 = 'path is not valid UTF-8'
      SEPARATOR = /[^a-z0-9-]+/
      EDGE_DASHES = /\A-+|-+\z/

      attr_reader :problems

      def initialize(runtime, context, group:, labels:, dry_run:)
        @store = runtime.store
        @git = runtime.git
        @home = File.expand_path(runtime.paths.home)
        @context = context
        @group = group
        @labels = labels
        @dry_run = dry_run
        @problems = []
      end

      def register(directory, depth:)
        raise Store::NotFound.of(Resources::GROUPS, @group) unless @store.group_available?(@group)

        scan = Scanner.scan(File.absolute_path(Paths.expand(directory, home: @home)), depth:)
        @problems.concat(scan.problems.map { "#{stored_path(it.path)}: #{it.detail}" })
        raise Error, format(NONE_FOUND, directory, depth) if scan.repositories.empty? && scan.problems.empty?

        index_registered
        scan.repositories.filter_map { entry(it) }
      end

      private

      # A failure is kept with the path it concerns, so the other repositories are still registered.
      def entry(path)
        shown = stored_path(path)
        raise Error, NOT_UTF8 unless path.valid_encoding?

        existing = @by_path[identity(path)]
        return Entry.new(project: existing, created: false) if existing

        Entry.new(project: create(path, shown), created: true)
      rescue Error => e
        @problems << problem(shown, e)
        nil
      end

      # A git error starts with the absolute path, which the line already names as the manifest would.
      def problem(shown, error)
        detail = error.is_a?(Git::Error) ? error.message.delete_prefix("#{error.path}: ") : error.message
        ["#{shown}: #{detail}", error.hint].compact.join('. ')
      end

      def create(path, shown)
        project = Project.new(name: claim(name_for(path)), group: @group, labels: @labels, path: shown,
                              remote: remote(path, shown))
        project = @store.create(project) unless @dry_run
        remember(project)
        project
      end

      def name_for(path)
        Names.validate!(File.basename(path).downcase.gsub(SEPARATOR, '-').gsub(EDGE_DASHES, ''), what: 'project name')
      end

      # The listing skips a manifest it cannot read, whose name the store still holds.
      def claim(name)
        taken = @by_name[name]
        raise Error, format(TAKEN, name, taken.path) if taken

        unreadable = @store.exist?(Resources::PROJECTS, name, group: @group)
        raise Store::Conflict, "project #{name.inspect} already exists" if unreadable

        name
      end

      # A manifest that cannot be read is reported the way get reports it.
      def index_registered
        @by_path = {}
        @by_name = {}
        @store.list(Resources::PROJECTS, group: @group) { Output.warning(@context, it.message) }.each { remember(it) }
      end

      # Slipway never expands a ~user path, so such a project holds its name but no directory.
      def remember(project)
        path = Paths.expand(project.path, home: @home)
        @by_path[identity(File.absolute_path(path))] = project if File.absolute_path?(path)
        @by_name[project.name] = project
      end

      # A clone reached through a symbolic link, or registered from a directory reached through
      # one, is still the same clone; a stored path that no longer resolves keeps its spelling.
      def identity(path)
        File.realpath(path)
      rescue SystemCallError
        path
      end

      # A remote that is refused once its credentials are dropped is left out rather than
      # failing the registration: the path alone is enough to track the clone. git config reads a
      # repository it distrusts or cannot open as one without an origin, so a missing origin is
      # trusted only once git has read the repository.
      def remote(path, shown)
        url = @git.remote_url(path)
        @git.status(path) if url.nil?
        url && Git::Url.validate!(Git::Url.without_credentials(url), field: ORIGIN_FIELD)
      rescue Git::Url::Invalid => e
        Output.warning(@context, "#{shown}: spec.remote left out: #{e.message}")
        nil
      end

      # Under HOME the path is written with ~/, so the manifest names the same clone on another machine.
      def stored_path(path)
        return '~' if path == @home
        return path unless path.start_with?("#{@home}/")

        "~/#{path.delete_prefix("#{@home}/")}"
      end
    end
  end
end
