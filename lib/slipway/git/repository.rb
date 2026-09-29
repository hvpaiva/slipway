# frozen_string_literal: true

module Slipway
  module Git
    class Repository
      STATUS_ARGS = %w[status --porcelain=v2 --branch --show-stash -z --untracked-files=normal --no-renames].freeze
      # Six NUL separated fields in the order Commit.parse expects; -z terminates the record.
      LOG_ARGS = ['log', '-1', '-z', '--format=%H%x00%h%x00%ct%x00%an%x00%ae%x00%s'].freeze
      REMOTE_ARGS = %w[config --get remote.origin.url].freeze
      # `git config --get` exits 1 when the key is absent, which is an answer, not a failure.
      ABSENT_KEY_STATUS = 1
      UNBORN_MESSAGE = 'does not have any commits yet'
      MESSAGE_LIMIT = 200

      def initialize(runner: Runner.new)
        @runner = runner
      end

      def status(path)
        Status.parse(run(path, *STATUS_ARGS).out)
      end

      def last_commit(path)
        result = run(path, *LOG_ARGS, accept: method(:unborn?))
        result.success? ? Commit.parse(result.out) : nil
      end

      def remote_url(path)
        result = run(path, *REMOTE_ARGS, accept: ->(failed) { failed.status == ABSENT_KEY_STATUS })
        result.success? ? result.out.chomp : nil
      end

      private

      # The spawn is skipped for a path that is not a directory, since git would only say the same.
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
        else Error.new(path, "git exited with status #{result.status}: #{first_line(result.err)}")
        end
      end

      # Git quotes the URL it failed on, credentials included, and a server can add lines of its
      # own. Redacting before the cut keeps a password from surviving as a truncated URL.
      def first_line(err) = Url.redact(err.lines.first.to_s.strip)[0, MESSAGE_LIMIT]
    end
  end
end
