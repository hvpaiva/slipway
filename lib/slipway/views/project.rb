# frozen_string_literal: true

require_relative '../git/url'
require_relative '../labels'
require_relative '../resources'
require_relative '../state'
require_relative '../output'

module Slipway
  module Views
    module Project
      DETACHED = '(detached)'
      ROLES = ->(header, value) { State.role(value) if header == 'STATUS' }

      def self.headers(wide: false, group: false, labels: false)
        columns = [*(['GROUP'] if group), 'NAME', 'BRANCH', 'STATUS', 'AGE']
        columns.push('PATH', 'HEAD', 'LAST-COMMIT') if wide
        columns << 'LABELS' if labels
        columns
      end

      # nil cells are fine: Table prints them as <none>.
      def self.row(inspection, now:, wide: false, group: false, labels: false)
        project = inspection.project
        cells = [*([project.group] if group), project.name, branch(inspection.status), inspection.state,
                 Output::Age.humanize(project.created_at, now)]
        cells.push(project.path, inspection.status&.head, last_commit_age(inspection.commit, now)) if wide
        cells << Labels.format(project.labels) if labels
        cells
      end

      def self.describe(inspection, now:)
        project = inspection.project
        [['Name', project.name], ['Group', project.group], ['Labels', project.labels],
         ['Created', project.created_at], ['Age', Output::Age.humanize(project.created_at, now)],
         ['Path', project.path], ['Description', project.description],
         ['Status', Output::Painted.new(role: State.role(inspection.state), text: inspection.state)],
         ['Repository', repository(inspection)], ['Last Commit', last_commit(inspection.commit)]]
      end

      # Fields git could not answer are left out, as kubectl leaves out unset fields.
      def self.object(inspection)
        status = inspection.status
        inspection.project.to_manifest.merge(
          'status' => plain(
            'branch' => status&.branch, 'head' => status&.head, 'upstream' => status&.upstream,
            'ahead' => status&.ahead, 'behind' => status&.behind, 'staged' => status&.staged,
            'unstaged' => status&.unstaged, 'untracked' => status&.untracked,
            'conflicted' => status&.conflicted, 'stashes' => status&.stashes,
            'state' => inspection.state, 'lastCommit' => commit_object(inspection.commit)
          ).compact
        )
      end

      def self.branch(status)
        return nil if status.nil?

        status.detached? ? DETACHED : status.branch
      end

      def self.last_commit_age(commit, now) = commit && Output::Age.humanize(commit.time, now)

      def self.repository(inspection)
        status = inspection.status
        return failure(inspection.error) if status.nil?

        [['Branch', branch(status)], ['Head', status.head], ['Upstream', status.upstream],
         ['Ahead', status.ahead], ['Behind', status.behind], ['Staged', status.staged],
         ['Unstaged', status.unstaged], ['Untracked', status.untracked],
         ['Conflicted', status.conflicted], ['Stashes', status.stashes],
         ['Remote', inspection.remote&.then { Git::Url.redact(it) }]]
      end

      # The Path line already shows the path, so it is cut from git's message.
      def self.failure(error)
        reason = error.message.delete_prefix("#{error.path}: ")
        error.respond_to?(:hint) && error.hint ? [reason, error.hint] : reason
      end

      def self.last_commit(commit)
        return nil if commit.nil?

        [['Hash', commit.sha], ['Author', "#{commit.author} <#{commit.email}>"],
         ['Date', Resources.timestamp(commit.time)], ['Subject', commit.subject]]
      end

      def self.commit_object(commit)
        return nil if commit.nil?

        plain('hash' => commit.sha, 'author' => commit.author, 'email' => commit.email,
              'date' => Resources.timestamp(commit.time), 'subject' => commit.subject)
      end

      # json and yaml escape what their syntax needs, not what a terminal obeys, and `jq -r`
      # prints a field as it is, so git's text is made plain here as it is in a table.
      def self.plain(fields) = fields.transform_values { it.is_a?(String) ? Output.plain(it) : it }

      private_class_method :branch, :last_commit_age, :repository, :failure, :last_commit, :commit_object, :plain
    end
  end
end
