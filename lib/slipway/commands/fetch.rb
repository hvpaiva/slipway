# frozen_string_literal: true

require_relative 'base'
require_relative 'results'
require_relative '../fetcher'
require_relative '../outcome'

module Slipway
  module Commands
    class Fetch < Base
      # Raised once every line has printed: the lines already say what went wrong, so it adds no
      # error line, only exit status 1.
      class Failed < Error
        def initialize = super(problems: [])
      end

      DESCRIPTION = "Fetch from the remote of each selected project.\n\n" \
                    'Runs git fetch in every project of the current group, in the projects named, in the ones ' \
                    'a label selector matches, or with --all-groups in every project. Git fetches from the ' \
                    'remote of the checked-out branch, else from the only remote, else from origin, as a git ' \
                    'fetch typed in the repository would, and updates the references that remote\'s fetch ' \
                    'refspecs name (remote-tracking references by default) and its tags, never the ' \
                    'checked-out branch or the working tree. The parallel setting caps how many projects ' \
                    "fetch at once, and the results print in the order the projects are listed.\n\n" \
                    'Each project prints one line, one of the results listed below, with a reason in parentheses ' \
                    'and the details under it. A project whose repository cannot be read, or in which git finds ' \
                    'no remote to fetch from, is skipped before git fetch runs. A project whose spec.paused is ' \
                    "true is paused: no git command runs in it.\n\n" \
                    'Git never prompts: a fetch that needs a password, a passphrase or a host key is denied, one ' \
                    'that runs past the networkTimeout setting is killed, and only the transports in the ' \
                    'protocols setting are allowed. The exit status is 1 when any project was denied or failed.'
      USAGE = '[NAME... | project/NAME...]'
      # In the order the closing summary counts them.
      ROLES = { Outcome::FETCHED => :result_changed, Outcome::UNCHANGED => :result_unchanged,
                Outcome::SKIPPED => :result_skipped, Outcome::PAUSED => :result_paused,
                Outcome::DENIED => :result_denied, Outcome::FAILED => :result_failed }.freeze

      RESULTS = CLI::Glossary.new(
        title: 'Results',
        intro: 'When more than one project ran, a count of the results closes the run on stderr. With ' \
               '--dry-run no remote is contacted: a project that would be fetched reads fetched, and every ' \
               'line and the count end in (dry run). Ctrl-C stops the git processes slipway started and exits with ' \
               'status 130.',
        entries: {
          Outcome::FETCHED => "The remote moved refs, and up to #{Fetcher::REF_LIMIT} follow: origin/main " \
                              'a1b2c3d..e4f5a6b for a ref that moved, origin/feature d09a085 (new) for a new one ' \
                              'and origin/feature deleted (was d09a085) for one --prune removed. A last line, and ' \
                              'N more, counts the rest. Tags appear under their bare name. With git before 2.41, ' \
                              'every fetch that succeeds reads fetched, without the refs.',
          Outcome::UNCHANGED => 'The remote answered and had nothing new.',
          "#{Outcome::SKIPPED} (Reason)" => 'No fetch ran: git could not read the repository (Missing, NotARepo, ' \
                                            'Unsafe, Unknown), git has no remote to pick because there is no ' \
                                            'upstream, no origin and either no remote or more than one ' \
                                            "(#{Fetcher::NO_REMOTE}), or the branch tracks a local branch " \
                                            '(LocalUpstream).',
          Outcome::PAUSED => 'spec.paused is true, so no git command ran in the project.',
          "#{Outcome::DENIED} (Reason)" => 'Git needed a password, a passphrase or a host key (AuthRequired). Run ' \
                                           'the git -C PATH fetch printed below it once in a terminal to see what ' \
                                           'git needs.',
          "#{Outcome::FAILED} (Reason)" => 'The fetch ran past networkTimeout (Timeout), used a transport ' \
                                           'protocols leaves out (ProtocolNotAllowed), or git failed for another ' \
                                           'reason (Unknown).'
        }
      )
      ALL_GROUPS = Options::ALL_GROUPS.with(summary: 'Fetch every project across all groups',
                                            description: 'If present, fetch every project across all groups. The ' \
                                                         'group in the current configuration is ignored even if ' \
                                                         'specified with --group.')
      PRUNE = CLI::Option.new(long: 'prune', description: 'Before fetching, remove any remote-tracking references ' \
                                                          'that no longer exist on the remote.')

      def self.command(factory)
        CLI::Command.new(
          name: 'fetch', summary: 'Fetch from the remote of each project', section: 'Repository Commands',
          description: DESCRIPTION, examples:, usage: USAGE, glossaries: [RESULTS],
          positionals: [Options.project_positional(factory)],
          options: [Options::SELECTOR, ALL_GROUPS, PRUNE, Options::DRY_RUN],
          handler: new(factory)
        )
      end

      def self.examples
        [
          CLI::Example.new(comment: 'Fetch every project in the current group', command: 'fetch'),
          CLI::Example.new(comment: 'Fetch every project in every group', command: 'fetch -A'),
          CLI::Example.new(comment: 'Fetch two projects of the work group', command: 'fetch api web -n work'),
          CLI::Example.new(comment: 'Fetch the projects labeled lang=rust and prune deleted branches',
                           command: 'fetch -l lang=rust --prune'),
          CLI::Example.new(comment: 'List the projects a fetch would reach, without contacting any remote',
                           command: 'fetch -A --dry-run')
        ]
      end
      private_class_method :examples

      def kinds = [Resources::PROJECTS]

      def run(runtime, context, args, opts)
        scope = scope(runtime, context, opts)
        names = scope.project_targets(args, verb: 'fetch')
        dry_run = opts[:dry_run] == true
        fetcher = Fetcher.new(runtime, prune: opts[:prune] == true, dry_run:)
        results = Results.new(context, ROLES, dry_run:)
        scope.select(Resources::PROJECTS, names) do |projects|
          next scope.report_none(Resources::PROJECTS) if projects.empty?

          results.stream(projects, workers: runtime.settings.parallel, work: fetcher.method(:attempt))
          results.summarize
        end
        raise Failed if results.any?(Outcome::DENIED, Outcome::FAILED)
      end
    end
  end
end
