# frozen_string_literal: true

require_relative 'git'
require_relative 'paths'
require_relative 'plan'
require_relative 'pool'
require_relative 'state'

module Slipway
  # +status+, +commit+ and +remote+ are nil when git could not answer; +error+ then holds the
  # Git error and +state+ its word. +fetched_at+ is nil then too, and for a repository no fetch
  # has reached. +operation+ is the merge, rebase or other operation in progress, asked only of a
  # project the plan would fast-forward. +pin+ is how far HEAD is from spec.revision, a
  # Git::Distance or nil when the repository lacks that commit, asked only of a pinned project
  # whose HEAD is elsewhere.
  Inspection = Data.define(:project, :status, :commit, :remote, :fetched_at, :state, :error, :operation, :pin) do
    def initialize(operation: nil, pin: nil, **) = super

    # A pin may name an annotated tag, which git peels to the commit it tags, so HEAD is also at
    # the pin when git counts no commit between them.
    def at_pin?
      return false if commit.nil? || project.revision.nil?

      commit.sha == project.revision || (!pin.nil? && pin.ahead.zero? && pin.behind.zero?)
    end

    def self.failed(project, error)
      new(project:, status: nil, commit: nil, remote: nil, fetched_at: nil, state: State.for_error(error), error:)
    end
  end

  # A leading ~ in a project path is +home+, the HOME of the environment the command runs in,
  # so a manifest written as ~/dev/x means the same thing whoever runs it.
  class Inspector
    # One warning per distinct reason a project came back Unknown: the message without its
    # path, so twenty projects without git raise one line.
    Batch = Data.define(:inspections, :warnings)

    DEFAULT_WORKERS = 8
    UNKNOWN = 'Unknown'

    def initialize(git:, clock:, home: Dir.home, workers: DEFAULT_WORKERS)
      @git = git
      @clock = clock
      @home = home
      @pool = Pool.new(workers:)
    end

    def workers = @pool.workers

    # A relative path has no directory to be relative to and a path that is not a directory
    # needs no git; both are Missing. Any other failure, git's or not, becomes the
    # Inspection's error rather than escaping the worker.
    def examine(project)
      path = Paths.expand(project.path, home: @home)
      return Inspection.failed(project, Git::RelativePath.new(path)) unless File.absolute_path?(path)
      return Inspection.failed(project, Git::MissingPath.new(path)) unless File.directory?(path)

      with_operation(with_pin(Inspection.new(project:, **query(path), error: nil), path), path)
    rescue Git::Error => e
      Inspection.failed(project, e)
    rescue StandardError => e
      Inspection.failed(project, Git::Error.new(path, "git could not be read: #{e.class}: #{e.message}"))
    end

    def examine_all(projects)
      results = @pool.map(projects) { examine(it) }.freeze
      Batch.new(inspections: results, warnings: collect_warnings(results))
    end

    private

    def query(path)
      status = @git.status(path)
      commit = status.unborn? ? nil : @git.last_commit(path)
      { status:, commit:, remote: @git.remote_url(path), fetched_at: @git.fetched_at(path),
        state: State.derive(status) }
    end

    # One more spawn, paid only by a pinned project whose HEAD is not the pinned commit, and a
    # second when HEAD is behind the pin on a branch whose upstream exists.
    def with_pin(inspection, path)
      revision = inspection.project.revision
      sha = inspection.commit&.sha
      return inspection if revision.nil? || sha.nil? || sha == revision

      inspection.with(pin: @git.distance(path, revision, tracking: inspection.status.tracking?))
    end

    # One more spawn, paid only by a project that would otherwise be fast-forwarded.
    def with_operation(inspection, path)
      return inspection unless Plan.for(inspection).fast_forward?

      inspection.with(operation: @git.in_progress(path))
    end

    def collect_warnings(results)
      results.select { it.state == UNKNOWN }.map { reason(it.error) }.uniq.freeze
    end

    def reason(error) = error.message.delete_prefix("#{error.path}: ")
  end
end
