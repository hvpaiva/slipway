# frozen_string_literal: true

require_relative 'base'
require_relative 'fetch'
require_relative 'results'
require_relative '../fetcher'
require_relative '../sync'

module Slipway
  module Commands
    # Named apart from Slipway::Sync, the executor it drives.
    class SyncCommand < Base
      # Raised once every line has printed: the lines already say what went wrong, so it adds no
      # error line, only exit status 1.
      class Failed < Error
        def initialize = super(problems: [])
      end

      DESCRIPTION = "Fetch each selected project and fast-forward its branch.\n\n" \
                    'Runs in every project of the current group, in the projects named, in the ones a label ' \
                    'selector matches, or with --all-groups in every project. Each project is fetched as slipway ' \
                    'fetch fetches it and compared with its manifest as slipway diff compares it, and its ' \
                    'checked-out branch is fast-forwarded onto its upstream when the branch tracks an upstream ' \
                    'that still exists, is behind it without commits of its own, has no staged, unstaged or ' \
                    'conflicted changes and no merge, rebase or other operation in progress. Untracked files do ' \
                    'not stop it, and git refuses a fast-forward that would overwrite one. Sync never merges, ' \
                    "rebases, stashes, resets, switches a branch or changes a remote.\n\n" \
                    'A project whose spec.syncPolicy is FetchOnly is only fetched, and one whose spec.paused is ' \
                    'true is left alone: no git command runs in it. A project pinned by spec.revision is ' \
                    'fast-forwarded up to that commit instead of its upstream, only when its upstream holds the ' \
                    "commit, never past it, and never moved back to it.\n\n" \
                    'Each project prints one line: fast-forwarded, fetched when the fetch of a FetchOnly project ' \
                    'brought references, unchanged, skipped, paused, denied or failed, with the reason in ' \
                    'parentheses and the details below. A fast-forward onto the upstream names the commits the ' \
                    'branch moved across and the command that undoes it. The parallel setting caps how many ' \
                    'projects fetch at once, fast-forwards run one at a time, and the results print in the ' \
                    "order the projects are listed.\n\n" \
                    'With --dry-run=client nothing is fetched or written: the plan is made from the last fetch.'
      USAGE = '[NAME... | project/NAME...]'
      EXIT_STATUSES = CLI::Manpage::EXIT_STATUSES.merge(
        '0' => 'Every selected project was fast-forwarded, fetched, left unchanged, skipped or paused.',
        '1' => 'Runtime error, such as a missing resource or an unreadable manifest, or a project whose fetch or ' \
               'fast-forward was denied or failed.'
      ).freeze
      # In the order the closing summary counts them.
      ROLES = { Sync::FAST_FORWARDED => :result_changed, Fetcher::FETCHED => :result_changed,
                Fetcher::UNCHANGED => :result_unchanged, Fetcher::SKIPPED => :result_skipped,
                Fetcher::PAUSED => :result_paused, Fetcher::DENIED => :result_denied,
                Fetcher::FAILED => :result_failed }.freeze
      ALL_GROUPS = Options::ALL_GROUPS.with(description: 'If present, sync every project across all groups. The ' \
                                                         'group in the current configuration is ignored even if ' \
                                                         'specified with --group.')

      def self.command(factory)
        CLI::Command.new(
          name: 'sync', summary: 'Fetch projects and fast-forward their branches', section: 'Repository Commands',
          description: DESCRIPTION, examples:, usage: USAGE, exit_statuses: EXIT_STATUSES,
          positionals: [Options.project_positional(factory)],
          options: [Options::SELECTOR, ALL_GROUPS, Fetch::PRUNE, Options::DRY_RUN],
          handler: new(factory)
        )
      end

      def self.examples
        [
          CLI::Example.new(comment: 'Sync every project in the current group', command: 'sync'),
          CLI::Example.new(comment: 'Sync every project in every group', command: 'sync -A'),
          CLI::Example.new(comment: 'Sync two projects of the work group', command: 'sync api web -n work'),
          CLI::Example.new(comment: 'Show what sync would do from the last fetch, without contacting any remote',
                           command: 'sync -A --dry-run=client')
        ]
      end
      private_class_method :examples

      def run(runtime, context, args, opts)
        scope = scope(runtime, context, opts)
        names = scope.project_targets(args, verb: 'sync')
        dry_run = opts[:dry_run] == 'client'
        fetcher = Fetcher.new(runtime, prune: opts[:prune] == true, dry_run:)
        executor = Sync::Executor.new(runtime, fetcher, dry_run:, group: configured_group(runtime, opts))
        results = Results.new(context, ROLES, dry_run:)
        scope.select(Resources::PROJECTS, names) do |projects|
          next scope.report_none(Resources::PROJECTS) if projects.empty?

          results.stream(projects, workers: runtime.config.parallel, work: executor.method(:observe)) do |step|
            executor.settle(step)
          end
          unfetched(context, executor.unfetched)
          results.summarize
        end
        raise Failed if results.any?(Fetcher::DENIED, Fetcher::FAILED)
      end

      private

      # config.group already holds a typed -n, and the undo line is run later without it.
      def configured_group(runtime, opts) = opts[:group] ? nil : runtime.config.group

      def unfetched(context, count)
        return if count.zero?

        subject = count == 1 ? '1 project was' : "#{count} projects were"
        Output.warning(context, "#{subject} never fetched and a dry run does not fetch; run 'slipway fetch' " \
                                'first for an up-to-date plan')
      end
    end
  end
end
