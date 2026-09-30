# frozen_string_literal: true

require_relative 'fetcher'
require_relative 'git'
require_relative 'paths'
require_relative 'plan'
require_relative 'rollout'

module Slipway
  # Moves a project's branch to a revision of its rollout history and holds the project there
  # with spec.revision, as kubectl rollout undo rewrites a Deployment's template to an earlier
  # revision. The manifest is written only once git has moved the branch.
  class Rollback
    # Where the branch is and where the chosen revision is, as the checks saw them. +distance+
    # counts the commits the move drops (ahead) or gains (behind).
    Step = Data.define(:project, :status, :head, :revision, :distance) do
      def back? = distance.ahead.positive?

      def forward? = !back? && distance.behind.positive?

      def count = back? ? distance.ahead : distance.behind
    end

    # A check that failed, turned into the project's skipped line.
    class Refused < StandardError
      attr_reader :reason, :values

      def initialize(reason, values)
        @reason = reason
        @values = values
        super(reason)
      end
    end

    ROLLED_BACK = 'rolled back'
    ACTION = Git::Repository::ROLLBACK_ACTION
    ABBREV = Git::Porcelain::ABBREVIATION
    HELD = 'held there by spec.revision'
    NOT_PINNED = 'NotPinned'
    # Each leaves the branch and the manifest as they were.
    REFUSALS = {
      'Conflicted' => '%<paths>s; finish or abort the merge first',
      'Detached' => 'HEAD is detached at %<head>s; undo moves only a checked-out branch',
      'Unborn' => 'no commits yet; nothing to roll back',
      'NoUpstream' => '%<branch>s tracks no upstream; undo drops only commits an upstream holds',
      'Gone' => 'upstream %<upstream>s no longer exists; undo drops only commits an upstream holds',
      'InProgress' => 'a %<operation>s is in progress',
      'NoHistory' => 'no rollout history found for %<branch>s',
      'NoPrevious' => 'no last revision to roll back to',
      'UnknownRevision' => 'unable to find specified revision %<number>d in history',
      'RevisionNotFound' => 'commit %<commit>s of revision %<number>d is not in this repository',
      'Diverged' => 'revision %<number>d is not on the history of %<branch>s; undo moves a branch only along it',
      'LocalCommits' => '%<branch>s has commits that are not on %<upstream>s; undo would drop them',
      'Dirty' => '%<changes>s; undo moves a branch back only without staged changes, and forward only without ' \
                 'staged or unstaged changes',
      'OffUpstream' => 'revision %<number>d is not on %<upstream>s; undo moves a branch forward only along its upstream'
    }.freeze
    # Git's own refusals, worded for a move either way.
    RELAYED = {
      'WouldLoseChanges' => 'the move would overwrite local changes; commit or move them and run undo again',
      'WouldOverwrite' => 'the move would overwrite untracked or ignored files; move them and run undo again'
    }.freeze
    KEEPS_LOCKS = 'undo never removes a lock'
    # Plain status hides an ignored file, and the move refuses one in its way.
    COMMANDS = { 'Conflicted' => %w[status], 'Detached' => %w[status], 'Gone' => %w[branch -vv],
                 'InProgress' => %w[status], 'LocalCommits' => %w[log --oneline @{upstream}..HEAD],
                 'Dirty' => %w[status], 'WouldLoseChanges' => %w[status],
                 'WouldOverwrite' => %w[status --ignored] }.freeze

    # +group+ is the one a command without -n selects, so the unpin command can leave it out; nil
    # when -n was typed, so the unpin command names the group.
    def initialize(runtime, dry_run:, group:)
      @runtime = runtime
      @dry_run = dry_run
      @group = group
    end

    # +number+ is a revision the history lists; nil or 0 is the one before the current one.
    def undo(project, number: nil)
      inspection = @runtime.inspector.examine(project)
      return Fetcher::Outcome.unreadable(project, inspection) if inspection.error

      ready(inspection)
      step = plan(inspection, number)
      @dry_run ? settled(step) : act(step)
    rescue Refused => e
      skipped(project, e.reason, format(REFUSALS.fetch(e.reason), **e.values))
    end

    private

    # The checks sync makes before it moves a branch, less the one for local changes, which
    # depends on the direction of the move.
    def ready(inspection)
      status = inspection.status
      refuse('Conflicted', paths: unmerged(status.conflicted)) if status.conflicted.positive?
      refuse('Detached', head: status.head) if status.detached?
      refuse('Unborn') if status.unborn?
      refuse('NoUpstream', branch: status.branch) if status.upstream.nil?
      refuse('Gone', upstream: status.upstream) if status.upstream_gone?
      operation = @runtime.git.in_progress(path(inspection.project))
      refuse('InProgress', operation:) if operation
    end

    def plan(inspection, number)
      project = inspection.project
      status = inspection.status
      head = inspection.commit.sha
      history = Rollout::History.new(@runtime.git.reflog(path(project), status.branch))
      revision = target(history, head, number, status.branch)
      distance = @runtime.git.distance(path(project), revision.sha, tracking: true)
      refuse('RevisionNotFound', commit: short(revision.sha), number: revision.number) if distance.nil?
      Step.new(project:, status:, head:, revision:, distance:).tap { check(it) }
    end

    def target(history, head, number, branch)
      revision = number.to_i.zero? ? history.previous(head) : history.revision(number)
      return revision if revision

      refuse('NoHistory', branch:) if history.empty?
      number.to_i.zero? ? refuse('NoPrevious') : refuse('UnknownRevision', number:)
    end

    # A move back must not drop a commit only this repository holds, nor a staged change, since
    # reset --keep resets every index entry; git itself refuses one that would lose an unstaged
    # change. A move forward is a fast-forward and needs what sync's fast-forward needs.
    def check(step)
      status = step.status
      values = { number: step.revision.number, branch: status.branch, upstream: status.upstream }
      back_ready(step, values) if step.back?
      forward_ready(step, values) if step.forward?
    end

    def back_ready(step, values)
      status = step.status
      refuse('Diverged', **values) if step.distance.behind.positive?
      refuse('LocalCommits', **values) if status.ahead.to_i.positive?
      refuse('Dirty', changes: "#{status.staged} staged") if status.staged.positive?
    end

    def forward_ready(step, values)
      status = step.status
      changes = { 'staged' => status.staged, 'unstaged' => status.unstaged }
                .filter_map { |kind, number| "#{number} #{kind}" if number.positive? }
      refuse('Dirty', changes: changes.join(', ')) unless changes.empty?
      refuse('OffUpstream', **values) if step.distance.off_upstream.to_i.positive?
    end

    def act(step)
      held(step, move(step))
    rescue Git::Blocked => e
      relayed(step.project, e)
    rescue Git::Error => e
      Fetcher::Outcome.failure(step.project, e)
    end

    def move(step)
      path = path(step.project)
      sha = step.revision.sha
      if step.back? then @runtime.git.roll_back(path, to: sha)
      elsif step.forward? then @runtime.git.fast_forward(path, onto: sha, reflog_action: ACTION)
      end
    end

    # The branch has moved by now, so a manifest that cannot be written says how to hold it there:
    # the same command with the revision named finds nothing to move and only writes the pin.
    def held(step, move)
      from = move&.from || step.head
      count = move&.count || 0
      pin(step)
      settled(step, from:, count:)
    rescue Error => e
      Fetcher::Outcome.new(project: step.project, word: Fetcher::FAILED, reason: NOT_PINNED,
                           details: [position(step, from, count), unpinned(step, e)])
    end

    def unpinned(step, error)
      retry_command = "#{Rollout.command('undo', step.project, @group)} --to-revision=#{step.revision.number}"
      "spec.revision was not written: #{error.message}; run '#{retry_command}' to hold it there"
    end

    def pin(step)
      project = step.project
      sha = step.revision.sha
      @runtime.store.save(project.with(revision: sha)) unless project.revision == sha
    end

    def settled(step, from: step.head, count: step.count)
      project = step.project
      changed = count.positive? || project.revision != step.revision.sha
      Fetcher::Outcome.new(project:, word: changed ? ROLLED_BACK : Fetcher::UNCHANGED,
                           details: ["#{position(step, from, count)}; #{HELD}", following(project, step.status)])
    end

    def position(step, from, count)
      revision = step.revision
      branch = step.status.branch
      target = short(revision.sha)
      return "#{branch} is already at #{target} (revision #{revision.number})" if count.zero?

      way = step.back? ? 'back' : 'forward'
      "#{branch} #{short(from)}..#{target} (#{commits(count)} #{way} to revision #{revision.number})"
    end

    def following(project, status) = "'#{Rollout.command('unpin', project, @group)}' follows #{status.upstream} again"

    def relayed(project, error)
      reason = error.reason
      detail = RELAYED.fetch(reason) do
        message = error.message.delete_prefix("#{error.path}: ")
        reason == 'Busy' ? "#{message}; #{KEEPS_LOCKS}" : message
      end
      skipped(project, reason, detail)
    end

    def skipped(project, reason, detail)
      words = COMMANDS[reason]
      Fetcher::Outcome.new(project:, word: Fetcher::SKIPPED, reason:,
                           details: [detail, words && Plan.git(project, *words)].compact)
    end

    def refuse(reason, **values) = raise(Refused.new(reason, values))

    def unmerged(count) = count == 1 ? '1 unmerged path' : "#{count} unmerged paths"

    def commits(count) = count == 1 ? '1 commit' : "#{count} commits"

    def short(sha) = sha[0, ABBREV]

    def path(project) = Paths.expand(project.path, home: @runtime.paths.home)
  end
end
