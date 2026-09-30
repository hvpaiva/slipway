# frozen_string_literal: true

require_relative 'base'
require_relative 'results'
require_relative '../fetcher'
require_relative '../rollback'

module Slipway
  module Commands
    module RolloutCommand
      class Undo < Base
        # Raised once the line has printed: it already says why, so this adds only exit status 1.
        class Failed < Error
          def initialize = super(problems: [])
        end

        DESCRIPTION = "Roll back a project to a previous revision.\n\n" \
                      'Moves the checked-out branch to the revision before the current one, or to the one ' \
                      '--to-revision names from slipway rollout history, and then writes that commit to ' \
                      'spec.revision, so sync holds the project there until slipway rollout unpin. The branch moves ' \
                      'back with git reset --keep, only when its upstream holds every commit the move drops, and ' \
                      'forward, to undo an undo, with git merge --ff-only. Untracked files and unstaged changes to ' \
                      'files the move leaves alone are kept; git refuses a move that would overwrite a local change ' \
                      'or an untracked file, and slipway refuses one that would overwrite an ignored file. A move ' \
                      'back skips a project with staged changes, and a move forward one with staged or unstaged ' \
                      "changes.\n\n" \
                      'A project whose HEAD is detached, whose branch has no commits or no upstream that exists, ' \
                      'that is in the middle of a merge, rebase or other operation, or whose branch has commits its ' \
                      'upstream lacks, is skipped with the reason and nothing is moved or written. A paused project ' \
                      "can be rolled back: pausing only keeps fetch and sync away.\n\n" \
                      'The project prints one line: rolled back, unchanged, skipped, denied or failed, with the ' \
                      'reason in parentheses and the details below. failed (NotPinned) means the branch moved but ' \
                      'spec.revision was not written, and the detail names the --to-revision command that writes ' \
                      "it without moving the branch again.\n\n" \
                      'With --dry-run=client nothing is moved or written.'
        EXIT_STATUSES = CLI::Manpage::EXIT_STATUSES.merge(
          '0' => 'The project was rolled back, or already stood at the revision and was held there.',
          '1' => 'Runtime error, such as a missing resource or an unreadable manifest, or a project that was ' \
                 'skipped or whose move was denied or failed.'
        ).freeze
        TO_REVISION = CLI::Option.new(long: 'to-revision', argument: 'N',
                                      description: 'The revision to roll back to, as slipway rollout history ' \
                                                   'numbers it. 0, the default, is the revision before the ' \
                                                   'current one.')
        REVISION_INVALID = 'invalid argument %p for --to-revision: must be a revision number, or 0'
        ROLES = { Rollback::ROLLED_BACK => :result_changed, Fetcher::UNCHANGED => :result_unchanged,
                  Fetcher::SKIPPED => :result_skipped, Fetcher::DENIED => :result_denied,
                  Fetcher::FAILED => :result_failed }.freeze

        def self.command(factory)
          CLI::Command.new(
            name: 'undo', summary: 'Undo a previous rollout', description: DESCRIPTION, usage: SINGLE_USAGE,
            examples:, exit_statuses: EXIT_STATUSES,
            positionals: [Options.project_positional(factory, variadic: false, required: true)],
            options: [TO_REVISION, Options::DRY_RUN],
            handler: new(factory)
          )
        end

        def self.examples
          [
            CLI::Example.new(comment: 'Roll back project hldr to the previous revision', command: 'rollout undo hldr'),
            CLI::Example.new(comment: 'Roll back project hldr to revision 3',
                             command: 'rollout undo hldr --to-revision=3'),
            CLI::Example.new(comment: 'Show where undo would move project hldr, without moving or writing anything',
                             command: 'rollout undo hldr --dry-run=client')
          ]
        end
        private_class_method :examples

        def run(runtime, context, args, opts)
          scope = scope(runtime, context, opts)
          names = scope.project_targets(args, verb: 'roll back')
          number = revision(opts[:to_revision])
          dry_run = opts[:dry_run] == 'client'
          rollback = Rollback.new(runtime, dry_run:, group: opts[:group] ? nil : runtime.config.group)
          results = Results.new(context, ROLES, dry_run:)
          scope.select(Resources::PROJECTS, names) do |projects|
            projects.each { results.report(rollback.undo(it, number:)) }
          end
          raise Failed if results.any?(Fetcher::SKIPPED, Fetcher::DENIED, Fetcher::FAILED)
        end

        private

        def revision(value)
          return if value.nil?

          number = Integer(value, 10, exception: false)
          number && !number.negative? ? number : raise(CLI::UsageError, format(REVISION_INVALID, value))
        end
      end
    end
  end
end
