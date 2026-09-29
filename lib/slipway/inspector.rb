# frozen_string_literal: true

require_relative 'git'
require_relative 'state'

module Slipway
  # What was learned about one project's repository. +status+, +commit+ and +remote+ are nil
  # when git could not answer; +error+ then holds the Git error and +state+ its word.
  Inspection = Data.define(:project, :status, :commit, :remote, :state, :error) do
    def self.failed(project, error)
      new(project:, status: nil, commit: nil, remote: nil, state: State.for_error(error), error:)
    end

    # True when git answered, whatever the repository looks like.
    def inspected? = !status.nil?
  end

  # Reads the git state of registered projects, several at a time, and reduces each to an
  # Inspection. Paths are resolved against +home+, the HOME of the environment the command
  # runs in, so a manifest written as ~/dev/x means the same thing whoever runs it.
  class Inspector
    DEFAULT_WORKERS = 8
    UNKNOWN = 'Unknown'
    TILDE = %r{\A~(?=/|\z)}

    attr_reader :workers
    # One line per distinct reason a project came back Unknown in the last inspect_all: the
    # message without its path, so twenty projects without git raise one warning.
    attr_reader :warnings

    def initialize(git:, clock:, home: Dir.home, workers: DEFAULT_WORKERS)
      @git = git
      @clock = clock
      @home = home
      @workers = workers
      @warnings = [].freeze
    end

    # Inspects one project. A path that is not a directory is Missing without asking git.
    # Without an argument this is Object#inspect, which Ruby calls when printing the object.
    def inspect(project = nil)
      return super() if project.nil?

      path = expand(project.path)
      return Inspection.failed(project, Git::MissingPath.new(path)) unless File.directory?(path)

      Inspection.new(project:, **query(path), error: nil)
    rescue Git::Error => e
      Inspection.failed(project, e)
    end

    # Inspects every project on a bounded pool of threads and returns the results in the
    # order the projects were given. Refreshes #warnings.
    def inspect_all(projects)
      results = Array.new(projects.size)
      queue = Queue.new
      projects.each_with_index { |project, index| queue << [project, index] }
      queue.close
      Array.new([@workers, projects.size].min) { worker(queue, results) }.each(&:join)
      @warnings = collect_warnings(results)
      results
    end

    # The absolute path a manifest's path refers to. A leading ~ is the runtime's home, not
    # the one Ruby started with; a relative path is taken from home as well.
    def expand(path) = File.absolute_path(path.sub(TILDE, @home), @home)

    private

    def query(path)
      status = @git.status(path)
      commit = status.unborn? ? nil : @git.last_commit(path)
      { status:, commit:, remote: @git.remote_url(path), state: State.derive(status) }
    end

    # Each worker drains the queue; Queue#pop returns nil once the queue is closed and empty.
    def worker(queue, results)
      Thread.new do
        while (job = queue.pop)
          project, index = job
          results[index] = inspect(project)
        end
      end
    end

    def collect_warnings(results)
      results.select { it.state == UNKNOWN }.map { reason(it.error) }.uniq.freeze
    end

    def reason(error) = error.message.delete_prefix("#{error.path}: ")
  end
end
