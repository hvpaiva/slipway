# frozen_string_literal: true

require_relative 'drift'
require_relative 'fetcher'
require_relative 'git'
require_relative 'plan'

module Slipway
  # Brings projects to their manifests by the one move that cannot lose work: each is fetched,
  # planned by Plan.for, and its checked-out branch fast-forwarded when the plan says so.
  module Sync
    FAST_FORWARDED = 'fast-forwarded'

    # Observes and plans on the workers and moves branches on the calling thread, one project at
    # a time, so no two writes ever run at once. The only caller of the git write.
    class Executor
      # The plan for a project whose fetch went through, made from what git answered after it.
      Observed = Data.define(:project, :inspection, :fetched, :plan)

      REACHED = [Fetcher::FETCHED, Fetcher::UNCHANGED].freeze
      ABBREV = Git::Porcelain::ABBREVIATION
      TO_PIN = '(to the pinned revision)'
      # Git leaves the branch where it was on each refusal. A lock may belong to a git that is
      # still running, so none is ever removed.
      ADVICE = { 'Busy' => 'sync never removes a lock', 'WouldOverwrite' => 'move them and run sync again',
                 'WouldLoseChanges' => 'commit or move them and run sync again',
                 'NotFastForward' => 'sync never merges or rebases' }.freeze

      # Dry-run projects that no fetch has reached, counted as they settle.
      attr_reader :unfetched

      def initialize(runtime, fetcher, dry_run:)
        @runtime = runtime
        @fetcher = fetcher
        @dry_run = dry_run
        @unfetched = 0
      end

      # Runs on a worker thread: an Outcome when nothing is left to do, else an Observed.
      def observe(project)
        return Fetcher::Outcome.new(project:, word: Fetcher::PAUSED) if project.paused

        inspection = @runtime.inspector.examine(project)
        return unreadable(inspection) if inspection.error

        fetched = @fetcher.fetch(project, inspection)
        return fetched unless REACHED.include?(fetched.word)

        inspection = @runtime.inspector.examine(project) unless @dry_run
        return unreadable(inspection) if inspection.error

        Observed.new(project:, inspection:, fetched:, plan: Plan.for(inspection))
      end

      # Runs on the calling thread, in the order the projects are listed.
      def settle(step)
        return step unless step.is_a?(Observed)

        @unfetched += 1 if @dry_run && step.inspection.fetched_at.nil?
        plan = step.plan
        return skipped(step) unless plan.skips.empty?
        return move(step) if plan.fast_forward?

        still(step)
      end

      private

      # The checks inside the fast-forward read the repository again right before git merges,
      # and --ff-only is git's own last word.
      def move(step)
        project = step.project
        plan = step.plan
        return outcome(project, FAST_FORWARDED, drift(plan.items)) if @dry_run

        onto = plan.to_revision? ? project.revision : Git::Repository::UPSTREAM
        forward = @fetcher.exclusively(project) { @runtime.git.fast_forward(@fetcher.path(project), onto:) }
        return still(step) unless forward.moved?

        outcome(project, FAST_FORWARDED, [moved(step, forward), *declared(plan)])
      rescue Git::Blocked => e
        refused(step, e)
      rescue Git::Error => e
        @fetcher.failure(project, e)
      end

      def moved(step, forward)
        range = "#{step.inspection.status.branch} #{forward.from[0, ABBREV]}..#{forward.to[0, ABBREV]}"
        return "#{range} #{TO_PIN}" if step.plan.to_revision?

        gained = forward.count
        undo = Plan.git(step.project, 'reset', '--keep', forward.from[0, ABBREV])
        "#{range} (#{gained} commit#{'s' unless gained == 1}); undo with '#{undo}'"
      end

      def refused(step, error)
        reason = error.reason
        detail = [error.message.delete_prefix("#{error.path}: "), ADVICE[reason]].compact.join('; ')
        command = Plan.git(step.project, 'status') unless reason == 'Busy'
        outcome(step.project, Fetcher::SKIPPED, [detail, command, *declared(step.plan)], reason:)
      end

      def skipped(step)
        blocker = step.plan.skips.first
        outcome(step.project, Fetcher::SKIPPED, [blocker.message, blocker.command, *declared(step.plan)],
                reason: blocker.type)
      end

      # Nothing moved, so the plan's drift says why. Only a FetchOnly project reports what its fetch
      # brought; for any other, sync reports the branch.
      def still(step)
        fetched = step.fetched if step.project.sync_policy == SyncPolicy::FETCH_ONLY
        outcome(step.project, fetched&.word || Fetcher::UNCHANGED,
                [*fetched&.details, held(step), *drift(step.plan.reports)])
      end

      def held(step)
        "held at #{step.project.revision[0, ABBREV]} by spec.revision" if step.inspection.at_pin?
      end

      # Worded as diff words it, with the command that shows or resolves it.
      def unreadable(inspection)
        item = Plan.for(inspection).items.first
        outcome(inspection.project, Fetcher::SKIPPED, [item.message, item.command], reason: item.type)
      end

      # A move or a blocker already says where the branch stands against its upstream or its pin.
      def declared(plan) = drift(plan.reports.reject { Drift::MOVES.include?(it.type) })

      def drift(items) = items.map { "#{it.type}: #{it.message}" }

      def outcome(project, word, details, reason: nil)
        Fetcher::Outcome.new(project:, word:, reason:, details: details.compact)
      end
    end
  end
end
