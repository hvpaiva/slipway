# frozen_string_literal: true

require_relative 'base'
require_relative '../inspector'
require_relative '../plan'

module Slipway
  module Commands
    class Diff < Base
      # Raised once every project has printed: the lines say what differs, so it adds no error
      # line, only the exit status a script tests.
      class Differs < Error
        def initialize = super(problems: [])

        def exit_status = 3
      end

      # A project that could not be compared, because its manifest could not be read or git could
      # not answer for it, must not pass for one in sync. The reason is already on stderr, so this
      # adds only exit status 1.
      class Unanswered < Error
        def initialize = super(problems: [])
      end

      DESCRIPTION = "Show where each selected project differs from its manifest.\n\n" \
                    'Compares every project of the current group, the projects named, the ones a label selector ' \
                    'matches, or with --all-groups every project, with its manifest. Each project that differs ' \
                    'prints its name and one line per difference: Missing, Remote, Branch, Revision or Behind, ' \
                    'then the blocker that keeps sync from fast-forwarding the branch, if any. A line is followed ' \
                    'by the git command that shows or resolves it when there is one; slipway never runs it. A ' \
                    "project that matches its manifest prints nothing.\n\n" \
                    'The repositories are read as they are on disk: diff contacts no remote and writes nothing, ' \
                    'so Behind is as of the last fetch, which slipway fetch refreshes. A project pinned by ' \
                    'spec.revision is compared with that commit instead of its upstream, and is blocked when the ' \
                    'repository lacks the commit, HEAD is past it or its upstream does not hold it. A paused or ' \
                    'FetchOnly project shows a blocker only when git cannot read its repository.'
      USAGE = '[NAME... | project/NAME...]'
      EXIT_STATUSES = CLI::Manpage::EXIT_STATUSES.merge(
        '0' => 'Every selected project matches its manifest.',
        '1' => 'Runtime error, such as a missing resource or an unreadable manifest, or a project whose state is ' \
               'Unknown because git failed or did not finish.',
        '3' => 'At least one selected project differs from its manifest or is blocked, including a directory that ' \
               'holds no repository (NotARepo) and a repository git refuses (Unsafe).'
      ).sort_by { |status, _| Integer(status) }.to_h.freeze
      INDENT = '  '
      COMMAND_INDENT = '    '
      ALL_GROUPS = Options::ALL_GROUPS.with(description: 'If present, compare every project across all groups with ' \
                                                         'its manifest. The group in the current configuration is ' \
                                                         'ignored even if specified with --group.')

      def self.command(factory)
        CLI::Command.new(
          name: 'diff', summary: 'Show where projects differ from their manifests', section: 'Repository Commands',
          description: DESCRIPTION, examples:, usage: USAGE, exit_statuses: EXIT_STATUSES,
          positionals: [Options.project_positional(factory)],
          options: [Options::SELECTOR, ALL_GROUPS],
          handler: new(factory)
        )
      end

      def self.examples
        [
          CLI::Example.new(comment: 'Show where the projects of the current group differ from their manifests',
                           command: 'diff'),
          CLI::Example.new(comment: 'Show every project that differs, in every group', command: 'diff -A'),
          CLI::Example.new(comment: 'Compare two projects of the work group', command: 'diff api web -n work'),
          CLI::Example.new(comment: 'Compare the projects labeled lang=rust', command: 'diff -l lang=rust')
        ]
      end
      private_class_method :examples

      def run(runtime, context, args, opts)
        scope = scope(runtime, context, opts)
        names = scope.project_targets(args, verb: 'diff')
        failure = nil
        scope.select(Resources::PROJECTS, names) do |projects|
          next scope.report_none(Resources::PROJECTS) if projects.empty?

          failure = compare(context, Base.examine(runtime, context, projects))
        end
        failure = Unanswered.new if scope.skipped?
        raise failure if failure
      end

      private

      def compare(context, inspections)
        plans = inspections.map { Plan.for(it) }
        inspections.zip(plans).each { |inspection, plan| report(context, inspection.project, plan) }
        return Unanswered.new if inspections.any? { it.state == Inspector::UNKNOWN }

        Differs.new unless plans.all?(&:converged?)
      end

      # Messages and commands arrive redacted; git's text in them is made plain here.
      def report(context, project, plan)
        return if plan.converged?

        lines = plan.items.flat_map do |item|
          word = context.paint(item.blocker ? :status_danger : :status_warning, "#{item.type}:")
          line = "#{INDENT}#{word} #{Output.plain(item.message)}"
          item.command ? [line, COMMAND_INDENT + context.paint(:muted, Output.plain(item.command))] : [line]
        end
        context.puts("#{Resources::PROJECTS.singular}/#{project.name}", *lines)
      end
    end
  end
end
