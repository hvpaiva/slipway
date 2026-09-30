# frozen_string_literal: true

require_relative 'errors'
require_relative 'move_back'

module Slipway
  module Git
    class Repository
      # The one reset slipway runs, and the checks around it. It shares the fast-forward's checks
      # of the repository's state, but lets unstaged changes through: reset --keep keeps an
      # unstaged change to a file the move leaves alone and refuses one to a file it rewrites.
      # It resets every index entry, though, so a staged change would be lost and is refused.
      module RollingBack
        ROLLBACK_ACTION = 'slipway rollout undo'
        RESET_ARGS = %w[reset --keep --quiet --no-recurse-submodules].freeze
        # Literal, so a name git would read as pathspec magic stays a name; icase, because on a
        # case-insensitive file system the file in the way may differ in case.
        LITERAL = ':(literal,icase)'

        # Moves the checked-out branch back to +to+, a full object name of a commit HEAD contains,
        # only when @{upstream} holds every commit the move drops. Raises Blocked, or a subclass for
        # git's own refusal, and the branch then stays where it was, or WriteTimeout as the
        # fast-forward does.
        def roll_back(path, to:, reflog_action: ROLLBACK_ACTION)
          unless FastForwarding::OBJECT_NAME.match?(to)
            raise ArgumentError, "to must be a full object name, not #{to.inspect}"
          end

          directory = File.expand_path(path)
          status = ready_status(directory, clean: false)
          raise Blocked.new(directory, 'Dirty', changes(status)) if status.staged.positive?

          from, to = revisions(directory, to)
          dropped, gained = position(directory, from, to)
          return MoveBack.new(from:, to: from, count: 0) if (dropped + gained).zero?

          behind_head(directory, status, to, gained)
          kept_upstream(directory, status, from)
          clear_way(directory, from, to)
          reset(directory, to, reflog_action)
          MoveBack.new(from:, to:, count: dropped)
        end

        private

        def behind_head(directory, status, commit, gained)
          return if gained.zero?

          short = commit[0, Porcelain::ABBREVIATION]
          raise Blocked.new(directory, 'Diverged', "commit #{short} is not on the history of #{status.branch}")
        end

        # Every commit the move drops stays reachable from the upstream, so none of them exists only
        # in this repository.
        def kept_upstream(directory, status, head)
          return if upstream_holds?(directory, head)

          raise Blocked.new(directory, 'LocalCommits',
                            "#{status.branch} has commits that are not on #{status.upstream}")
        end

        # reset --keep refuses to overwrite an untracked file but replaces an ignored one, whose
        # content was never committed, so the paths the move adds are checked for either first.
        def clear_way(directory, from, to)
          added = run(directory, 'diff', '--name-only', '-z', '--no-renames', '--diff-filter=A', from, to, '--')
          suspects = added.out.split("\0").flat_map { in_the_way(directory, it) }.uniq
          return if suspects.empty?

          others = run(directory, 'ls-files', '-z', '--others', '--', *suspects.map { LITERAL + it })
          raise WouldOverwrite, directory unless others.out.empty?
        end

        # The entries on disk git would have to replace to write +path+: the path itself, and any
        # parent directory that is a file or a symbolic link instead. ls-files then tells whether
        # git tracks them.
        def in_the_way(directory, path)
          parts = path.split('/')
          parents = (1...parts.size).map { parts.first(it).join('/') }
          [*parents.reject { real_directory?(File.join(directory, it)) }, path].select do |entry|
            File.symlink?(File.join(directory, entry)) || File.exist?(File.join(directory, entry))
          end
        end

        def real_directory?(path) = File.directory?(path) && !File.symlink?(path)

        # A partial clone fetches the blobs the reset writes, so it runs as the merge does.
        def reset(directory, commit, reflog_action)
          result = run(directory, *Runner::NETWORK_CONFIG, *RESET_ARGS, commit, '--',
                       accept: method(:refusal), network: true, timeout: @network_timeout,
                       env: @network_environment.merge(FastForwarding::REFLOG_VARIABLE => reflog_action))
          raise refusal(result), directory unless result.success?
        rescue Timeout
          raise WriteTimeout.new(directory, seconds: @network_timeout)
        end
      end
    end
  end
end
