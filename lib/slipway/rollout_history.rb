# frozen_string_literal: true

require_relative 'git'
require_relative 'resources'

module Slipway
  # The revisions of a branch, read from the moves slipway left in its reflog. Git keeps the
  # history, so slipway stores none of its own.
  class RolloutHistory
    # Every move slipway makes runs with GIT_REFLOG_ACTION set to "slipway <action>", and git
    # writes "<action>: <what it did>".
    ACTION = /\Aslipway ([^:]+):/
    SYNC = 'sync'
    UNDO = 'rollout undo'

    # A commit the branch pointed at just before or just after a move slipway made. `action` names
    # that move ("sync", "rollout undo"), or is nil for where the branch stood before slipway moved
    # it; `from` is the commit the move started from, nil when the reflog no longer holds it.
    Revision = Data.define(:number, :sha, :time, :action, :from)

    # The rollout command that acts on `project`. It names the project's group unless that is
    # `group`, the one a command typed without -n selects.
    def self.command(verb, project, group)
      command = "slipway rollout #{verb} #{Resources::PROJECTS.singular}/#{project.name}"
      project.group == group ? command : "#{command} -n #{project.group}"
    end

    attr_reader :revisions

    # `entries` are Git::ReflogEntry values, newest first as git lists them. Revisions count from
    # the oldest entry git still keeps.
    def initialize(entries)
      @revisions = []
      [nil, *entries.reverse].each_cons(2) { |before, entry| record(entry, before) }
      @revisions.freeze
    end

    def empty? = revisions.empty?

    def revision(number) = revisions.find { it.number == number }

    # The revision before the current one. A HEAD at the newest revision makes that one the
    # current; a HEAD that moved on without slipway makes the newest the one before.
    def previous(head)
      newest = revisions.last
      newest&.sha == head ? revisions[-2] : newest
    end

    # The revision an undo returned to: the newest earlier one at the same commit.
    def undone_to(revision) = revisions.first(revision.number - 1).reverse.find { it.sha == revision.sha }

    # The newest revision at `sha`, the one spec.revision holds.
    def pinned(sha) = revisions.reverse.find { it.sha == sha }

    private

    def record(entry, before)
      action = entry.subject[ACTION, 1]
      return unless action

      add(before, nil, nil) if before && @revisions.last&.sha != before.sha
      add(entry, action, before&.sha)
    end

    def add(entry, action, from)
      @revisions << Revision.new(number: @revisions.size + 1, sha: entry.sha, time: entry.time, action:, from:)
    end
  end
end
