# frozen_string_literal: true

require_relative 'git'
require_relative 'paths'
require_relative 'state'

module Slipway
  # What was learned about one project's repository. +status+, +commit+ and +remote+ are nil
  # when git could not answer; +error+ then holds the Git error and +state+ its word.
  Inspection = Data.define(:project, :status, :commit, :remote, :state, :error) do
    # An Inspection for a project git could not describe, worded by State.for_error.
    def self.failed(project, error)
      new(project:, status: nil, commit: nil, remote: nil, state: State.for_error(error), error:)
    end
  end

  # Reads the git state of registered projects, several at a time, and reduces each to an
  # Inspection. A leading ~ in a path is +home+, the HOME of the environment the command runs
  # in, so a manifest written as ~/dev/x means the same thing whoever runs it.
  class Inspector
    # The inspections of one examine_all, in input order, and one warning per distinct reason
    # a project came back Unknown: the message without its path, so twenty projects without
    # git raise one line.
    Batch = Data.define(:inspections, :warnings)

    DEFAULT_WORKERS = 8
    UNKNOWN = 'Unknown'

    attr_reader :workers

    def initialize(git:, clock:, home: Dir.home, workers: DEFAULT_WORKERS)
      @git = git
      @clock = clock
      @home = home
      @workers = workers
    end

    # Examines one project. A relative path has no directory to be relative to and a path
    # that is not a directory needs no git; both are Missing. Any other failure, git's or
    # not, becomes the Inspection's error rather than escaping the worker.
    def examine(project)
      path = Paths.expand(project.path, home: @home)
      return Inspection.failed(project, Git::RelativePath.new(path)) unless File.absolute_path?(path)
      return Inspection.failed(project, Git::MissingPath.new(path)) unless File.directory?(path)

      Inspection.new(project:, **query(path), error: nil)
    rescue Git::Error => e
      Inspection.failed(project, e)
    rescue StandardError => e
      Inspection.failed(project, Git::Error.new(path, "git could not be read: #{e.class}: #{e.message}"))
    end

    # Examines every project on a bounded pool of threads and returns a Batch whose
    # inspections are in the order the projects were given.
    def examine_all(projects)
      results = Array.new(projects.size)
      queue = Queue.new
      projects.each_with_index { |project, index| queue << [project, index] }
      queue.close
      Array.new([@workers, projects.size].min) { worker(queue, results) }.each(&:join)
      Batch.new(inspections: results.freeze, warnings: collect_warnings(results))
    end

    private

    def query(path)
      status = @git.status(path)
      commit = status.unborn? ? nil : @git.last_commit(path)
      { status:, commit:, remote: @git.remote_url(path), state: State.derive(status) }
    end

    # Each worker drains the queue; Queue#pop returns nil once the queue is closed and empty.
    # Nothing is expected to escape examine, and if something does the main thread reports
    # it once instead of every worker printing its own trace.
    def worker(queue, results)
      Thread.new do
        Thread.current.report_on_exception = false
        while (job = queue.pop)
          project, index = job
          results[index] = examine(project)
        end
      end
    end

    def collect_warnings(results)
      results.select { it.state == UNKNOWN }.map { reason(it.error) }.uniq.freeze
    end

    def reason(error) = error.message.delete_prefix("#{error.path}: ")
  end
end
