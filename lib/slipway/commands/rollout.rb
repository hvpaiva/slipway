# frozen_string_literal: true

require_relative 'base'
require_relative 'rollout_undo'
require_relative 'rollout_spec'
require_relative '../paths'
require_relative '../rollout_history'

module Slipway
  module Commands
    module Rollout
      DESCRIPTION = "Manage the rollout of a project.\n\n" \
                    'Slipway records a revision each time it moves the checked-out branch of a project: every ' \
                    'fast-forward of slipway sync and every slipway rollout undo leaves an entry in the ' \
                    "branch's reflog, and the commit the branch stood at before such a move is a revision too. " \
                    'rollout history lists the revisions, rollout undo returns the branch to one of them and ' \
                    'holds the project there with spec.revision, and rollout unpin lets sync follow the upstream ' \
                    'again. rollout pause keeps fetch and sync away from a project until rollout resume.'
      SINGLE_USAGE = '(NAME | project/NAME)'
      MANY_USAGE = '(NAME... | project/NAME...)'

      def self.command(factory)
        CLI::Command.new(
          name: 'rollout', summary: 'Manage the rollout of a project', section: 'Repository Commands',
          description: DESCRIPTION,
          subcommands: [History, Undo, Unpin, Pause, Resume].map { it.command(factory) }
        )
      end

      class History < Base
        DESCRIPTION = "View the rollout history of a project.\n\n" \
                      'Lists the revisions of the checked-out branch, oldest first: each commit slipway moved the ' \
                      'branch to, read from the entries of the branch\'s reflog whose subject starts with ' \
                      '"slipway ", and the commit the branch stood at before such a move. REVISION numbers them ' \
                      'from the oldest entry git still keeps, COMMIT is the commit, DATE the time the branch ' \
                      'moved there, CHANGE-CAUSE the move slipway made, and PINNED marks the revision spec.revision ' \
                      "holds the project at. Nothing is fetched or written.\n\n" \
                      'The history lasts as long as git keeps the reflog (gc.reflogExpire, 90 days by default; ' \
                      'slipway never runs gc), and git keeps none under core.logAllRefUpdates=false. A project ' \
                      'without history prints a notice on stderr and exits with status 0.'
        HEADERS = %w[REVISION COMMIT DATE CHANGE-CAUSE PINNED].freeze
        EMPTY = 'No rollout history found for %s.'
        DETACHED = '%s: HEAD is detached at %s; rollout history reads the reflog of the checked-out branch'
        ABBREV = Git::Porcelain::ABBREVIATION

        def self.command(factory)
          CLI::Command.new(
            name: 'history', summary: 'View rollout history', description: DESCRIPTION, usage: SINGLE_USAGE,
            examples: [
              CLI::Example.new(comment: 'View the rollout history of project hldr', command: 'rollout history hldr'),
              CLI::Example.new(comment: 'View the rollout history of project api in the work group',
                               command: 'rollout history project/api -n work')
            ],
            positionals: [Options.project_positional(factory, variadic: false, required: true)],
            handler: new(factory)
          )
        end

        def kinds = [Resources::PROJECTS]

        def run(runtime, context, args, opts)
          scope = scope(runtime, context, opts)
          names = scope.project_targets(args, verb: 'view the rollout history of')
          scope.select(Resources::PROJECTS, names) { |projects| projects.each { show(runtime, context, it) } }
        end

        private

        def show(runtime, context, project)
          name = "#{Resources::PROJECTS.singular}/#{project.name}"
          path = Paths.expand(project.path, home: runtime.paths.home)
          history = RolloutHistory.new(entries(runtime, project, name, path))
          return context.warn(context.paint_err(:muted, format(EMPTY, name))) if history.empty?

          pinned = history.pinned(project.revision)
          rows = history.revisions.map { row(runtime, path, history, it, pinned) }
          Output::Table.new(context, headers: HEADERS).print(rows)
        end

        def row(runtime, path, history, revision, pinned)
          [revision.number, revision.sha[0, ABBREV], Resources.timestamp(revision.time),
           cause(runtime, path, history, revision), revision.equal?(pinned)]
        end

        # A branch without commits has no reflog yet, and so no history.
        def entries(runtime, project, name, path)
          inspection = runtime.inspector.examine(project)
          raise inspection.error if inspection.error

          status = inspection.status
          raise Error, format(DETACHED, name, status.head) if status.detached?

          runtime.git.reflog(path, status.branch)
        end

        def cause(runtime, path, history, revision)
          case revision.action
          when nil then nil
          when RolloutHistory::SYNC then "sync: fast-forward#{gained(runtime, path, revision)}"
          when RolloutHistory::UNDO
            undone = history.undone_to(revision)
            undone ? "rollout undo to revision #{undone.number}" : RolloutHistory::UNDO
          else revision.action
          end
        end

        def gained(runtime, path, revision)
          count = revision.from && runtime.git.commits_between(path, revision.from, revision.sha)
          count ? " #{count} commit#{'s' unless count == 1}" : ''
        end
      end
    end
  end
end
