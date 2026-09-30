# frozen_string_literal: true

require_relative 'base'
require_relative 'results'
require_relative '../fetcher'

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
                    'Each project prints one line: fetched, unchanged when the remote had nothing new, skipped, ' \
                    'paused, denied or failed, with the reason in parentheses and the details below. A project ' \
                    'whose repository cannot be read, or in which git finds no remote to fetch from, is skipped ' \
                    'before git fetch runs. A project whose spec.paused is true is paused: no git command runs ' \
                    "in it.\n\n" \
                    'Git never prompts: a fetch that needs a password, a passphrase or a host key is denied, one ' \
                    'that runs past the networkTimeout setting is killed, and only the transports in the ' \
                    'protocols setting are allowed. The exit status is 1 when any project was denied or failed.'
      USAGE = '[NAME... | project/NAME...]'
      FETCHED = Fetcher::FETCHED
      UNCHANGED = Fetcher::UNCHANGED
      SKIPPED = Fetcher::SKIPPED
      PAUSED = Fetcher::PAUSED
      DENIED = Fetcher::DENIED
      FAILED = Fetcher::FAILED
      # In the order the closing summary counts them.
      ROLES = { FETCHED => :result_changed, UNCHANGED => :result_unchanged, SKIPPED => :result_skipped,
                PAUSED => :result_paused, DENIED => :result_denied, FAILED => :result_failed }.freeze

      ALL_GROUPS = Options::ALL_GROUPS.with(description: 'If present, fetch every project across all groups. The ' \
                                                         'group in the current configuration is ignored even if ' \
                                                         'specified with --group.')
      PRUNE = CLI::Option.new(long: 'prune', description: 'Before fetching, remove any remote-tracking references ' \
                                                          'that no longer exist on the remote.')

      def self.command(factory)
        CLI::Command.new(
          name: 'fetch', summary: 'Fetch from the remote of each project', section: 'Repository Commands',
          description: DESCRIPTION, examples:, usage: USAGE,
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
                           command: 'fetch -A --dry-run=client')
        ]
      end
      private_class_method :examples

      def run(runtime, context, args, opts)
        scope = scope(runtime, context, opts)
        names = scope.project_targets(args, verb: 'fetch')
        dry_run = opts[:dry_run] == 'client'
        fetcher = Fetcher.new(runtime, prune: opts[:prune] == true, dry_run:)
        results = Results.new(context, ROLES, dry_run:)
        scope.select(Resources::PROJECTS, names) do |projects|
          next scope.report_none(Resources::PROJECTS) if projects.empty?

          results.stream(projects, workers: runtime.config.parallel, work: fetcher.method(:attempt))
          results.summarize
        end
        raise Failed if results.any?(DENIED, FAILED)
      end
    end
  end
end
