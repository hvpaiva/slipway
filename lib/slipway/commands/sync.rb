# frozen_string_literal: true

require_relative 'base'
require_relative 'manual'
require_relative 'fetch'
require_relative 'results'
require_relative '../fetcher'
require_relative '../outcome'
require_relative '../syncer'

module Slipway
  module Commands
    class Sync < Base
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
                    'Each project prints one line, one of the results listed below, with a reason in parentheses ' \
                    'and the details under it. The parallel setting caps how many projects fetch at once, ' \
                    'fast-forwards run one at a time, and the results print in the order the projects are ' \
                    "listed.\n\n" \
                    'With --dry-run nothing is fetched or written: the plan is made from the last fetch.'
      USAGE = '[NAME... | project/NAME...]'
      EXIT_STATUSES = Manual::EXIT_STATUSES.merge(
        '0' => 'Every selected project was fast-forwarded, fetched, left unchanged, skipped or paused.',
        '1' => 'Runtime error, such as a missing resource or an unreadable manifest, or a project whose fetch or ' \
               'fast-forward was denied or failed.'
      ).freeze
      RESULTS = CLI::Glossary.new(
        title: 'Results',
        intro: 'When more than one project ran, a count of the results closes the run on stderr. With ' \
               '--dry-run every line and the count end in (dry run). Ctrl-C stops the git processes slipway ' \
               'started and exits with status 130; a fast-forward it stops ends as one stopped at the deadline.',
        entries: {
          Syncer::FAST_FORWARDED => 'The branch moved. For a move onto the upstream, the detail names the commits ' \
                                    'it gained, as main a1b2c3d..e4f5a6b (3 commits), and the command that undoes ' \
                                    "the move; a move up to a spec.revision pin ends in #{Syncer::TO_PIN}.",
          Outcome::FETCHED => 'The fetch of a FetchOnly project moved refs; the refs follow as in slipway fetch.',
          Outcome::UNCHANGED => 'The branch stayed where it was and nothing blocked it; the fetch may still have ' \
                                'moved remote-tracking refs.',
          "#{Outcome::SKIPPED} (Reason)" => 'The branch stayed where it was: a blocker stopped it, under the name ' \
                                            'slipway diff gives it; git refused the fast-forward (WouldOverwrite ' \
                                            'for untracked files in the way, WouldLoseChanges for local changes git ' \
                                            'status does not show, Busy for a lock another git process holds on ' \
                                            'the index, HEAD or the branch, NotFastForward for a branch that ' \
                                            'gained a commit since the check); or the project was skipped before ' \
                                            'its fetch, as in slipway fetch (Missing, NotARepo, Unsafe, Unknown, ' \
                                            'NoRemote, LocalUpstream).',
          Outcome::PAUSED => 'spec.paused is true, so no git command ran in the project.',
          "#{Outcome::DENIED} (Reason)" => 'The fetch or the fast-forward needed a password, a passphrase or a ' \
                                           'host key (AuthRequired), as in slipway fetch.',
          "#{Outcome::FAILED} (Reason)" => 'The fetch or the fast-forward ran past networkTimeout (Timeout), used ' \
                                           'a transport protocols leaves out (ProtocolNotAllowed), or git failed ' \
                                           'for another reason (Unknown). A fast-forward stopped at the deadline ' \
                                           'leaves the branch where it was, but the files git had already written ' \
                                           'stay in the working tree, and the detail names the command that lists ' \
                                           'them.'
        }
      )
      # In the order the closing summary counts them.
      ROLES = { Syncer::FAST_FORWARDED => :result_changed, Outcome::FETCHED => :result_changed,
                Outcome::UNCHANGED => :result_unchanged, Outcome::SKIPPED => :result_skipped,
                Outcome::PAUSED => :result_paused, Outcome::DENIED => :result_denied,
                Outcome::FAILED => :result_failed }.freeze
      ALL_GROUPS = Options::ALL_GROUPS.with(description: 'If present, sync every project across all groups. The ' \
                                                         'group in the current configuration is ignored even if ' \
                                                         'specified with --group.')

      def self.command(factory)
        CLI::Command.new(
          name: 'sync', summary: 'Fetch projects and fast-forward their branches', section: 'Repository Commands',
          description: DESCRIPTION, examples:, usage: USAGE, exit_statuses: EXIT_STATUSES, glossaries: [RESULTS],
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
                           command: 'sync -A --dry-run')
        ]
      end
      private_class_method :examples

      def kinds = [Resources::PROJECTS]

      def run(runtime, context, args, opts)
        scope = scope(runtime, context, opts)
        names = scope.project_targets(args, verb: 'sync')
        dry_run = opts[:dry_run] == true
        fetcher = Fetcher.new(runtime, prune: opts[:prune] == true, dry_run:)
        syncer = Syncer.new(runtime, fetcher, dry_run:, group: configured_group(runtime, opts))
        results = Results.new(context, ROLES, dry_run:)
        scope.select(Resources::PROJECTS, names) do |projects|
          next scope.report_none(Resources::PROJECTS) if projects.empty?

          results.stream(projects, workers: runtime.settings.parallel, work: syncer.method(:observe)) do |step|
            syncer.settle(step)
          end
          unfetched(context, syncer.unfetched)
          results.summarize
        end
        raise Failed if results.any?(Outcome::DENIED, Outcome::FAILED)
      end

      private

      # settings.group already holds a typed -n, and the undo line is run later without it.
      def configured_group(runtime, opts) = opts[:group] ? nil : runtime.settings.group

      def unfetched(context, count)
        return if count.zero?

        subject = count == 1 ? '1 project was' : "#{count} projects were"
        Output.warning(context, "#{subject} never fetched and a dry run does not fetch; run 'slipway fetch' " \
                                'first for an up-to-date plan')
      end
    end
  end
end
