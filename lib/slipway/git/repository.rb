# frozen_string_literal: true

require_relative 'fast_forwarding'
require_relative 'reflog'
require_relative 'rolling_back'
require_relative 'runner'

module Slipway
  module Git
    class Repository
      include FastForwarding
      include RollingBack

      STATUS_ARGS = %w[status --porcelain=v2 --branch --show-stash -z --untracked-files=normal --no-renames].freeze
      # Six NUL separated fields in the order Commit.parse expects; -z terminates the record.
      LOG_ARGS = ['log', '-1', '-z', '--format=%H%x00%h%x00%ct%x00%an%x00%ae%x00%s'].freeze
      REMOTE_ARGS = %w[config --get remote.origin.url].freeze
      # No remote argument: git fetches the remote of the current branch, else the only remote,
      # else origin, as the user's own `git fetch` would, so nothing from a manifest reaches this
      # argv. --no-all overrides fetch.all (git 2.44 and later), under which git would fetch every
      # remote and --atomic would refuse to run.
      FETCH_ARGS = %w[--no-all --atomic --no-recurse-submodules --no-auto-maintenance].freeze
      # A branch that tracks another local branch has "." as its remote, and a remote-less fetch
      # would read the repository itself: no remote-tracking ref moves, yet FETCH_HEAD is rewritten.
      UPSTREAM_REMOTE_ARGS = ['for-each-ref', '--format=%(HEAD)%(upstream:remotename)', 'refs/heads/'].freeze
      CURRENT_LOCAL_UPSTREAM = '*.'
      # ls-remote without a remote picks one the way fetch does, and --get-url prints its URL
      # without contacting it; with none to pick, git dies with this message, untranslated.
      DEFAULT_REMOTE_ARGS = %w[ls-remote --get-url].freeze
      NO_DEFAULT_REMOTE = 'No remote configured'
      # Git learned `fetch --porcelain` in 2.41. An older git rejects the option as a usage error
      # before it connects, and the fetch runs again without it.
      PORCELAIN = '--porcelain'
      PORCELAIN_UNKNOWN = /\Aerror: unknown option .porcelain'$/
      USAGE_STATUS = 129
      FETCH_HEAD = 'FETCH_HEAD'
      COMMON_DIR_ARGS = %w[rev-parse --git-common-dir].freeze
      # `git config --get` exits 1 when the key is absent, which is an answer, not a failure.
      ABSENT_KEY_STATUS = 1
      UNBORN_MESSAGE = 'does not have any commits yet'
      MESSAGE_LIMIT = 200
      NETWORK_TIMEOUT = 60
      PROTOCOLS = %w[ssh https].freeze
      PROTOCOLS_SOURCE = '"protocols" in the configuration file'
      # What git and ssh print when credentials or a host key are missing, would need a prompt, or
      # were refused by the remote.
      AUTH_REQUIRED = Regexp.union('terminal prompts disabled', 'could not read Username', 'could not read Password',
                                   'Authentication failed', 'Permission denied (publickey',
                                   'Host key verification failed', 'returned error: 403')
      # Git refuses a transport before it connects, so a real refusal is the whole of stderr and
      # ends in die(). Over ssh the remote writes to the same stream, and a line it prints is
      # followed by git's own message or ends in a signal (128 plus its number).
      PROTOCOL_REFUSED = /\Afatal: transport '(?<protocol>[a-z][a-z0-9+.-]*)' not allowed\n\z/
      DIE_STATUS = 128
      # The paths git keeps in the git directory of a worktree while an operation waits for the
      # user, in the order they are checked; the applying marker tells git am from a rebase. A
      # rebase that stops on a merge also leaves MERGE_HEAD, and it is the rebase that must be
      # continued or aborted.
      IN_PROGRESS = { 'rebase-apply/applying' => 'git am session', 'rebase-apply' => 'rebase',
                      'rebase-merge' => 'rebase', 'MERGE_HEAD' => 'merge', 'BISECT_LOG' => 'bisect' }.freeze
      # The reftable backend keeps these in its ref store, where no path names them.
      IN_PROGRESS_REFS = { 'CHERRY_PICK_HEAD' => 'cherry-pick', 'REVERT_HEAD' => 'revert' }.freeze
      # A cherry-pick or revert of several commits is still under way after `git reset` drops its
      # pseudoref, and git names it by the first command left in the sequencer's todo.
      SEQUENCER_TODO = 'sequencer/todo'
      SEQUENCER_COMMANDS = { 'pick' => 'cherry-pick', 'revert' => 'revert' }.freeze
      LAZY_FETCH_VARIABLE = 'GIT_NO_LAZY_FETCH'
      # A partial clone fetches an object it lacks from its remote, even for a read. --missing
      # stops that on every supported git; GIT_NO_LAZY_FETCH, which git honors from 2.44, and an
      # empty GIT_ALLOW_PROTOCOL, which refuses every transport before it connects, stand behind it.
      OFFLINE_REV_LIST = %w[rev-list --missing=allow-any].freeze
      REFLOG_ARGS = ['reflog', 'show', '-z', *Reflog::FORMAT].freeze
      BAD_REVISION = 'bad revision'
      OFFLINE_READ = { LAZY_FETCH_VARIABLE => '1', Runner::PROTOCOL_VARIABLE => '' }.freeze

      def initialize(runner: Runner.new, network_timeout: NETWORK_TIMEOUT, protocols: PROTOCOLS,
                     protocols_source: PROTOCOLS_SOURCE)
        @runner = runner
        @network_timeout = network_timeout
        @network_environment = Runner.network_environment(protocols)
        @protocols_source = protocols_source
        # Cleared once git turns out to predate --porcelain; threads racing on it only repeat
        # the rejected attempt.
        @porcelain = true
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

      def fetch(path, prune:)
        raise LocalUpstream, File.expand_path(path) if local_upstream?(path)

        options = [*FETCH_ARGS, *('--prune' if prune)]
        if @porcelain
          result = network_fetch(path, PORCELAIN, *options, accept: method(:porcelain_unknown?))
          return FetchResult.parse(result.out) if result.success?

          @porcelain = false
        end
        network_fetch(path, *options)
        FetchResult.new(updates: nil)
      end

      def local_upstream?(path)
        run(path, *UPSTREAM_REMOTE_ARGS).out.lines(chomp: true).include?(CURRENT_LOCAL_UPSTREAM)
      end

      def default_remote?(path)
        run(path, *DEFAULT_REMOTE_ARGS, accept: method(:no_default_remote?)).success?
      end

      # The operation git is in the middle of in this worktree, such as "rebase", or nil.
      def in_progress(path)
        directory = File.expand_path(path)
        operation(directory, git_paths(directory, *IN_PROGRESS.keys, SEQUENCER_TODO))
      end

      # How far HEAD is from `revision`, a full object name, or nil when the repository holds no
      # commit by that name. `tracking` says the branch has an upstream that exists, and a HEAD
      # behind the revision then also learns how many of its commits the upstream lacks.
      def distance(path, revision, tracking: false)
        unless OBJECT_NAME.match?(revision)
          raise ArgumentError, "revision must be a full object name, not #{revision.inspect}"
        end

        ahead, behind = offline_count(path, "HEAD...#{revision}^{commit}", '--left-right')
        return if ahead.nil?

        counted = tracking && ahead.zero? && behind.positive?
        off_upstream = offline_count(path, "#{UPSTREAM}..#{revision}^{commit}").first if counted
        Distance.new(ahead:, behind:, off_upstream:)
      end

      # The moves git logged for `branch`, newest first. Git answers "bad revision" for a branch
      # without commits, and logs nothing under core.logAllRefUpdates=false unless a log exists.
      def reflog(path, branch)
        result = run(path, *REFLOG_ARGS, "refs/heads/#{branch}", '--',
                     accept: ->(failed) { failed.err.include?(BAD_REVISION) })
        result.success? ? Reflog.parse(result.out) : []
      end

      # How many commits `to` reaches that `from` does not, both full object names, or nil when the
      # repository lacks either.
      def commits_between(path, from, to)
        [from, to].each do |name|
          raise ArgumentError, "expected a full object name, not #{name.inspect}" unless OBJECT_NAME.match?(name)
        end
        offline_count(path, "#{from}^{commit}..#{to}^{commit}").first
      end

      # nil for a repository that was never fetched or whose last fetch failed: git empties
      # FETCH_HEAD before it contacts the remote and writes a line for each ref it fetched.
      # Every worktree shares the remote-tracking refs, but git writes FETCH_HEAD in the worktree
      # that ran the fetch, so the newest one dates them.
      def fetched_at(path)
        head = fetch_heads(File.expand_path(path)).filter_map { File.stat(it) if File.file?(it) }.max_by(&:mtime)
        head.mtime.utc if head && !head.zero?
      end

      # Symlinks are resolved, so projects on one repository name the same directory however
      # their paths are written. A .git directory is read without a spawn, so listing projects
      # costs no extra git process.
      def common_dir(path)
        directory = File.expand_path(path)
        git_dir = File.join(directory, '.git')
        return File.realpath(git_dir) if File.directory?(git_dir)

        File.realpath(run(directory, *COMMON_DIR_ARGS).out.chomp, directory)
      end

      private

      # The spawn is skipped for a path that is not a directory, since git would only say the same.
      def run(path, *, accept: nil, network: false, **)
        directory = File.expand_path(path)
        raise MissingPath, directory unless File.directory?(directory)

        result = @runner.run(directory, *, **)
        return result if result.success? || accept&.call(result)

        raise classify(directory, result, network:)
      end

      # The counts rev-list prints for `range`, or none when it names an object the repository lacks.
      def offline_count(path, range, *options)
        result = run(path, *OFFLINE_REV_LIST, *options, '--count', range,
                     accept: ->(failed) { failed.err.include?(UNKNOWN_REVISION) }, env: OFFLINE_READ)
        result.success? ? result.out.split.map { Integer(it) } : []
      end

      def network_fetch(path, *, accept: nil)
        run(path, *Runner::NETWORK_CONFIG, 'fetch', *, accept:, network: true,
                                                       timeout: @network_timeout, env: @network_environment)
      end

      # base: keeps glob metacharacters in the repository path literal.
      def fetch_heads(directory)
        common = common_dir(directory)
        worktrees = File.join(common, 'worktrees')
        [File.join(common, FETCH_HEAD), *Dir.glob("*/#{FETCH_HEAD}", base: worktrees).map { File.join(worktrees, it) }]
      end

      def git_paths(directory, *names)
        paths = run(directory, 'rev-parse', *names.flat_map { ['--git-path', it] }).out.lines(chomp: true)
        paths.map { File.expand_path(it, directory) }
      end

      # `paths` holds the path of each IN_PROGRESS marker, then of the sequencer's todo.
      def operation(directory, paths)
        *markers, todo = paths
        IN_PROGRESS.values.zip(markers).find { |_, marker| File.exist?(marker) }&.first ||
          IN_PROGRESS_REFS.find { |ref, _| ref?(directory, ref) }&.last ||
          sequence(todo)
      end

      # rev-parse -q --verify exits 1 without a word for a ref that does not exist.
      def ref?(directory, ref)
        run(directory, 'rev-parse', '-q', '--verify', ref, accept: ->(failed) { failed.status == 1 }).success?
      end

      # The todo holds commit subjects, which need not be UTF-8.
      def sequence(todo)
        SEQUENCER_COMMANDS.fetch(File.binread(todo)[/\S+/], 'cherry-pick')
      rescue Errno::ENOENT, Errno::ENOTDIR
        nil
      end

      def unborn?(result) = result.err.include?(UNBORN_MESSAGE)

      def porcelain_unknown?(result) = result.status == USAGE_STATUS && PORCELAIN_UNKNOWN.match?(result.err)

      def no_default_remote?(result) = result.status == DIE_STATUS && result.err.include?(NO_DEFAULT_REMOTE)

      def classify(path, result, network:)
        failure = network ? network_failure(path, result) : local_failure(path, result)
        failure || Error.new(path, "git exited with status #{result.status}: #{first_line(result.err)}")
      end

      # Git's stderr under LC_ALL=C opens with a stable phrase for each local failure Slipway
      # names. A network command's stderr may open with what ssh or the remote printed, so these
      # phrases describe the local repository only for a command that never leaves the machine.
      def local_failure(path, result)
        case result.err
        when /\Afatal: not a git repository/ then NotARepository.new(path)
        when /\Afatal: cannot change to/ then MissingPath.new(path)
        when /\Afatal: detected dubious ownership/ then UnsafeRepository.new(path)
        end
      end

      def network_failure(path, result)
        refusal = PROTOCOL_REFUSED.match(result.err) if result.status == DIE_STATUS
        return ProtocolNotAllowed.new(path, protocol: refusal[:protocol], source: @protocols_source) if refusal

        refused = result.err.each_line.find { AUTH_REQUIRED.match?(it) }
        AuthRequired.new(path, redacted(refused)) if refused
      end

      def first_line(err) = redacted(err.lines.first)

      # Git quotes the URL it failed on, credentials included, and a server can add lines of its
      # own. Redacting before the cut keeps a password from surviving as a truncated URL.
      def redacted(line) = Url.redact(line.to_s.strip)[0, MESSAGE_LIMIT]
    end
  end
end
