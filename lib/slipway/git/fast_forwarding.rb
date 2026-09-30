# frozen_string_literal: true

require_relative 'errors'

module Slipway
  module Git
    class Repository
      # The one write to a working tree, and the checks and refusals around it. It runs through
      # Repository's own runner, status and in-progress lookup.
      module FastForwarding
        UPSTREAM = '@{upstream}'
        REFLOG_ACTION = 'slipway sync'
        REFLOG_VARIABLE = 'GIT_REFLOG_ACTION'
        # Abbreviations are refused: one that is unique today can name two commits tomorrow.
        OBJECT_NAME = /\A(?:[0-9a-f]{40}|[0-9a-f]{64})\z/
        # --no-autostash overrides merge.autoStash, under which git would stash local changes and
        # leave a conflicted tree behind when they no longer apply. --no-overwrite-ignore: by
        # default git replaces or removes an ignored file that stands in the way of an incoming
        # path, and that content was never committed.
        MERGE_ARGS = %w[merge --ff-only --no-stat --quiet --no-autostash --no-overwrite-ignore].freeze
        UNKNOWN_REVISION = 'unknown revision'
        # Git's refusals under LC_ALL=C. Each leaves the branch, the index and the working tree as
        # they were.
        REFUSALS = {
          /^(?:error|fatal): Unable to create '.*index\.lock': File exists/ => Busy,
          /^error: The following untracked working tree files would be (?:overwritten|removed)/ => WouldOverwrite,
          /^error: Updating the following directories would lose untracked files/ => WouldOverwrite,
          /^error: Your local changes to the following files would be overwritten/ => WouldLoseChanges,
          /^error: Entry '.*' not uptodate\. Cannot merge/ => WouldLoseChanges,
          /^fatal: Not possible to fast-forward/ => NotFastForward
        }.freeze

        # +onto+ is @{upstream} or a full object name its upstream holds. Raises Blocked, or a
        # subclass for git's own refusal, and the branch then stays where it was. Raises
        # WriteTimeout when the deadline stops git partway through the checkout: the branch stays
        # too, but the files git had written stay in the working tree.
        def fast_forward(path, onto: UPSTREAM, reflog_action: REFLOG_ACTION)
          unless onto == UPSTREAM || OBJECT_NAME.match?(onto)
            raise ArgumentError, "onto must be #{UPSTREAM} or a full object name, not #{onto.inspect}"
          end

          directory = File.expand_path(path)
          status = ready_status(directory)
          from, to = revisions(directory, onto)
          ahead, behind = position(directory, from, to)
          return FastForward.new(from:, to: from, count: 0) if behind.zero?

          target = onto == UPSTREAM ? status.upstream : to[0, Porcelain::ABBREVIATION]
          raise Blocked.new(directory, 'Diverged', "#{ahead} ahead, #{behind} behind #{target}") if ahead.positive?

          along_upstream(directory, to, status.upstream) unless onto == UPSTREAM
          merge(directory, to, reflog_action)
          FastForward.new(from:, to:, count: behind)
        end

        private

        def ready_status(directory)
          status = status(directory)
          blocker = blocker(status)
          raise Blocked.new(directory, *blocker) if blocker

          locks = branch_locks(status.branch)
          paths = git_paths(directory, *IN_PROGRESS.keys, SEQUENCER_TODO, *locks)
          operation = operation(directory, paths.shift(IN_PROGRESS.size + 1))
          raise Blocked.new(directory, 'InProgress', "#{operation} in progress") if operation

          held = locks.zip(paths).find { |_, lock| File.exist?(lock) }&.first
          raise Busy.new(directory, held) if held

          status
        end

        # Git takes these when it updates the branch, after it has checked out the new tree and
        # written the index, so one left behind would leave the tree moved and the branch not.
        def branch_locks(branch) = ['HEAD.lock', "refs/heads/#{branch}.lock", 'reftable/tables.list.lock']

        # In State.derive's order, so a blocking state is named as the STATUS column names it.
        # Untracked files do not block: git refuses to overwrite one.
        def blocker(status)
          return ['Conflicted', unmerged(status.conflicted)] if status.conflicted.positive?
          return ['Detached', "HEAD is detached at #{status.head}"] if status.detached?
          return ['Unborn', 'no commits yet'] if status.unborn?
          return ['Dirty', changes(status)] unless (status.staged + status.unstaged).zero?
          return ['NoUpstream', "#{status.branch} tracks no upstream"] if status.upstream.nil?

          ['Gone', "upstream #{status.upstream} no longer exists"] if status.upstream_gone?
        end

        def unmerged(count) = count == 1 ? '1 unmerged path' : "#{count} unmerged paths"

        def changes(status) = "#{status.staged} staged, #{status.unstaged} unstaged"

        # The merge names the commit the checks saw, not @{upstream}: a fetch running beside it
        # could move the upstream in between, and the branch would then move further than checked.
        def revisions(directory, onto)
          missing = ->(failed) { onto != UPSTREAM && failed.err.include?(UNKNOWN_REVISION) }
          result = run(directory, 'rev-parse', 'HEAD', "#{onto}^{commit}", accept: missing)
          return result.out.split if result.success?

          raise Blocked.new(directory, 'RevisionNotFound', "commit #{onto} is not in this repository")
        end

        def position(directory, from, to)
          run(directory, 'rev-list', '--left-right', '--count', "#{from}...#{to}").out.split.map { Integer(it) }
        end

        # A commit the upstream lacks could come from any branch or fork the repository has
        # fetched, so a named commit is reached only along the upstream.
        def along_upstream(directory, commit, upstream)
          lacks = ->(failed) { failed.status == 1 }
          return if run(directory, 'merge-base', '--is-ancestor', commit, UPSTREAM, accept: lacks).success?

          short = commit[0, Porcelain::ABBREVIATION]
          raise Blocked.new(directory, 'OffUpstream', "commit #{short} is not on #{upstream}")
        end

        # A partial clone fetches the blobs a checkout needs, so the merge runs as a network command:
        # no prompt, the allowed protocols only, and the network deadline. The deadline cannot tell
        # that fetch from the write, and a smudge filter such as git-lfs's may contact a server too.
        def merge(directory, commit, reflog_action)
          result = run(directory, *Runner::NETWORK_CONFIG, *MERGE_ARGS, commit,
                       accept: method(:refusal), network: true, timeout: @network_timeout,
                       env: @network_environment.merge(REFLOG_VARIABLE => reflog_action))
          raise refusal(result), directory unless result.success?
        rescue Timeout
          raise WriteTimeout.new(directory, seconds: @network_timeout)
        end

        def refusal(result) = REFUSALS.find { |pattern, _| pattern.match?(result.err) }&.last
      end
    end
  end
end
