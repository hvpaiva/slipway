# frozen_string_literal: true

module Slipway
  module Git
    # Answers Slipway's three questions about a working tree by running git through a Runner
    # and turning git's failures into the error classes of this module.
    class Repository
      STATUS_ARGS = %w[status --porcelain=v2 --branch --show-stash -z --untracked-files=normal --no-renames].freeze
      # Six NUL separated fields in the order Commit.parse expects; -z terminates the record.
      LOG_ARGS = ['log', '-1', '-z', '--format=%H%x00%h%x00%ct%x00%an%x00%ae%x00%s'].freeze
      REMOTE_ARGS = %w[config --get remote.origin.url].freeze
      # `git config --get` exits 1 when the key is absent, which is an answer, not a failure.
      ABSENT_KEY_STATUS = 1
      UNBORN_MESSAGE = 'does not have any commits yet'

      def initialize(runner: Runner.new)
        @runner = runner
      end

      # Status of the working tree at +path+; one git process.
      def status(path)
        Status.parse(run(path, *STATUS_ARGS).out)
      end

      # The commit at HEAD, or nil when the branch has no commits yet.
      def last_commit(path)
        result = run(path, *LOG_ARGS, accept: method(:unborn?))
        result.success? ? Commit.parse(result.out) : nil
      end

      # URL of the remote called origin, or nil when there is none.
      def remote_url(path)
        result = run(path, *REMOTE_ARGS, accept: ->(failed) { failed.status == ABSENT_KEY_STATUS })
        result.success? ? result.out.chomp : nil
      end

      private

      # Runs git at +path+ and returns its Result when it succeeded or when +accept+ says the
      # failure is an answer; any other failure is raised as the matching Git error. The spawn
      # is skipped for a path that is not a directory, since git would only say the same.
      def run(path, *, accept: nil)
        directory = File.expand_path(path)
        raise MissingPath, directory unless File.directory?(directory)

        result = @runner.run(directory, *)
        return result if result.success? || accept&.call(result)

        raise classify(directory, result)
      end

      def unborn?(result) = result.err.include?(UNBORN_MESSAGE)

      # Git's stderr under LC_ALL=C starts with a stable phrase for each failure Slipway names.
      def classify(path, result)
        case result.err
        when /\Afatal: not a git repository/ then NotARepository.new(path)
        when /\Afatal: cannot change to/ then MissingPath.new(path)
        when /\Afatal: detected dubious ownership/ then UnsafeRepository.new(path)
        else Error.new(path, "git exited with status #{result.status}: #{result.err.lines.first.to_s.strip}")
        end
      end
    end
  end
end
