# frozen_string_literal: true

require 'shellwords'
require_relative 'drift'
require_relative 'git'
require_relative 'paths'
require_relative 'resources'

module Slipway
  # What differs between a project and its manifest, and what sync would do about it, read from
  # one Inspection. It runs no git and reads no file, so every verb that shows drift reads the
  # same answer.
  module Plan
    # +actions+ is the drift sync resolves, +reports+ the drift it leaves as it is, and +skips+
    # the blockers that stop it.
    Result = Data.define(:actions, :skips, :reports) do
      def items = [*(actions + reports).sort_by { Drift::TYPES.index(it.type) }, *skips]

      def fast_forward? = actions.any? { it.type == Drift::BEHIND }

      def converged? = items.empty?
    end

    def self.for(inspection) = Planner.new(inspection).result

    class Planner
      ABBREVIATION = Git::Porcelain::ABBREVIATION
      FAST_FORWARD = 'sync will fast-forward'
      FETCH_ONLY = "syncPolicy is #{SyncPolicy::FETCH_ONLY}".freeze
      PAUSED = 'the project is paused'
      KEEPS_REMOTE = 'sync never changes a remote'

      def initialize(inspection)
        @inspection = inspection
        @project = inspection.project
        @status = inspection.status
      end

      def result
        return unreadable(@inspection.error) if @inspection.error

        declared = [remote, branch, revision].compact
        # A pinned revision replaces the upstream as what the branch should match.
        return outcome(reports: declared) if @project.revision

        following(declared)
      end

      private

      def outcome(actions: [], skips: [], reports: []) = Result.new(actions:, skips:, reports:)

      # A paused or FetchOnly project is never moved, so nothing can block it.
      def following(declared)
        held = hold
        return outcome(reports: [*declared, *behind(held)]) if held

        position = unfollowable
        return outcome(reports: declared, skips: [position]) if position
        return outcome(reports: declared) unless behind?

        blocker = obstacle
        return outcome(reports: [*declared, *behind], skips: [blocker]) if blocker

        outcome(actions: behind(FAST_FORWARD), reports: declared)
      end

      def hold
        return PAUSED if @project.paused

        FETCH_ONLY if @project.sync_policy == SyncPolicy::FETCH_ONLY
      end

      def behind? = @status.behind.to_i.positive?

      def behind(consequence = nil)
        return [] unless behind?

        message = "#{count(@status.behind, 'commit')} behind #{@status.upstream}"
        [Drift::Item.new(type: Drift::BEHIND, message: [message, consequence].compact.join('; '))]
      end

      # Without a branch that tracks an upstream that still exists, nothing says where the branch
      # should be.
      def unfollowable
        upstream = @status.upstream
        return Drift.blocker('Detached', head: @status.head, command: git('status')) if @status.detached?
        return Drift.blocker('Unborn') if @status.unborn?
        return Drift.blocker('Gone', upstream:, command: git('branch', '-vv')) if @status.upstream_gone?

        no_upstream if upstream.nil?
      end

      # The operation in progress is known only for a project that would otherwise fast-forward,
      # so it is checked last.
      def obstacle
        return conflicted if @status.conflicted.positive?
        return dirty if @status.staged.positive? || @status.unstaged.positive?
        return diverged if @status.ahead.to_i.positive?

        Drift.blocker('InProgress', operation: @inspection.operation, command: git('status')) if @inspection.operation
      end

      def unreadable(error)
        case error
        when Git::RelativePath then outcome(reports: [missing(reason(error), clone: false)])
        when Git::MissingPath then outcome(reports: [missing("no directory at #{@project.path}")])
        when Git::NotARepository then outcome(skips: [Drift.blocker('NotARepo', path: @project.path)])
        when Git::UnsafeRepository
          outcome(skips: [Drift.blocker('Unsafe', reason: reason(error), command: error.command)])
        else outcome(skips: [Drift.blocker('Unknown', reason: reason(error))])
        end
      end

      def missing(message, clone: true)
        url = @project.remote
        command = "git clone -- #{Shellwords.escape(url)} #{shell_path}" if clone && url
        Drift::Item.new(type: Drift::MISSING, message:, command:)
      end

      def remote
        wanted = @project.remote
        actual = @inspection.remote
        return if wanted.nil? || actual == wanted

        url = Shellwords.escape(wanted)
        if actual.nil?
          return Drift::Item.new(type: Drift::REMOTE, message: "no origin, manifest says #{wanted}; #{KEEPS_REMOTE}",
                                 command: git('remote', 'add', 'origin', url))
        end

        Drift::Item.new(type: Drift::REMOTE, message: "origin is #{actual}, manifest says #{wanted}; #{KEEPS_REMOTE}",
                        command: git('remote', 'set-url', 'origin', url))
      end

      def branch
        wanted = @project.branch
        actual = @status.branch
        return if wanted.nil? || actual == wanted

        head = actual ? "HEAD is on #{actual}" : 'HEAD is detached'
        Drift::Item.new(type: Drift::BRANCH, message: "#{head}, manifest says #{wanted}; sync never switches branches",
                        command: git('switch', Shellwords.escape(wanted)))
      end

      def revision
        wanted = @project.revision
        sha = @inspection.commit&.sha
        return if wanted.nil? || sha == wanted

        head = sha ? "HEAD is at #{sha[0, ABBREVIATION]}" : 'HEAD has no commits'
        Drift::Item.new(type: Drift::REVISION, message: "#{head}, manifest pins #{wanted[0, ABBREVIATION]}")
      end

      # The command names origin, so it is offered only when origin exists, and only for a branch
      # name that cannot reach the shell as anything but a word.
      def no_upstream
        name = @status.branch
        if @inspection.remote && Git::BranchName.valid?(name)
          command = git('branch', "--set-upstream-to=origin/#{name}")
        end
        Drift.blocker('NoUpstream', branch: name, command:)
      end

      def conflicted
        Drift.blocker('Conflicted', paths: count(@status.conflicted, 'unmerged path'), command: git('status'))
      end

      def dirty
        changes = { 'staged' => @status.staged, 'unstaged' => @status.unstaged }
                  .filter_map { |kind, number| "#{number} #{kind}" if number.positive? }.join(', ')
        Drift.blocker('Dirty', changes:, command: git('status'))
      end

      def diverged
        Drift.blocker('Diverged', ahead: @status.ahead, behind: @status.behind, upstream: @status.upstream,
                                  command: git('log', '--oneline', '--left-right', 'HEAD...@{upstream}'))
      end

      def count(number, noun) = "#{number} #{noun}#{'s' unless number == 1}"

      def reason(error) = error.message.delete_prefix("#{error.path}: ")

      def git(*words) = ['git', '-C', shell_path, *words].join(' ')

      # The path as the manifest writes it, so the line matches what was registered. Only the part
      # after ~ is quoted, since a shell does not expand a quoted ~.
      def shell_path
        path = @project.path
        rest = path.sub(Paths::TILDE, '')
        return Shellwords.escape(path) if rest == path

        rest.empty? ? '~' : "~#{Shellwords.escape(rest)}"
      end
    end
    private_constant :Planner
  end
end
