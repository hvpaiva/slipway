# frozen_string_literal: true

require_relative 'base'
require_relative '../git'
require_relative '../paths'
require_relative '../pool'
require_relative '../state'

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
      FETCHED = 'fetched'
      UNCHANGED = 'unchanged'
      SKIPPED = 'skipped'
      PAUSED = 'paused'
      DENIED = 'denied'
      FAILED = 'failed'
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
        session = Session.new(runtime, context, prune: opts[:prune] == true, dry_run: opts[:dry_run] == 'client')
        scope.select(Resources::PROJECTS, names) do |projects|
          projects.empty? ? scope.report_none(Resources::PROJECTS) : session.run(projects)
        end
        raise Failed if session.failed?
      end

      class Session
        Outcome = Data.define(:project, :word, :reason, :details)

        # With no remote to pick, git fetch exits 0 and prints nothing, which would read as unchanged.
        NO_REMOTE = 'NoRemote'
        NO_REMOTE_DETAIL = 'no upstream, no origin and no single remote to fetch from'
        ERROR_WORDS = { Git::AuthRequired => DENIED, Git::LocalUpstream => SKIPPED }.freeze
        REASONS = { Git::AuthRequired => 'AuthRequired', Git::LocalUpstream => 'LocalUpstream',
                    Git::Timeout => 'Timeout', Git::ProtocolNotAllowed => 'ProtocolNotAllowed' }.freeze
        REF_LIMIT = 5
        ABBREV = 7
        ZERO_ID = /\A0+\z/
        SHORT_REF = %r{\Arefs/(?:remotes|tags|heads)/}
        INDENT = '  '
        DRY_RUN = '(dry run)'

        def initialize(runtime, context, prune:, dry_run:)
          @runtime = runtime
          @context = context
          @prune = prune
          @dry_run = dry_run
          @tally = Hash.new(0)
          @locks = Hash.new { |locks, key| locks[key] = Mutex.new }
          @guard = Mutex.new
        end

        # Ruby buffers a stdout that is not a terminal: a pipe would see the lines only at exit,
        # after the summary on stderr, and since Ruby flushes stdout before it spawns, a line a
        # closed pipe refused would stay in the buffer and fail every later git with EPIPE.
        def run(projects)
          @context.unbuffer
          Pool.new(workers: @runtime.config.parallel).each_ordered(projects, method(:attempt)) do |outcome|
            report(outcome)
            @tally[outcome.word] += 1
          end
          summarize(projects.size) if projects.size > 1
        end

        def failed? = @tally.key?(DENIED) || @tally.key?(FAILED)

        private

        # Runs on a worker thread. An error git reports becomes the project's outcome; anything
        # else is a bug and leaves through the pool.
        def attempt(project)
          return outcome(project, PAUSED) if project.paused

          inspection = @runtime.inspector.examine(project)
          return unreadable(project, inspection) if inspection.error
          return outcome(project, SKIPPED, NO_REMOTE, [NO_REMOTE_DETAIL]) if remoteless?(project, inspection)
          return rehearse(project) if @dry_run

          fetched(project, exclusively(path(project)) { @runtime.git.fetch(path(project), prune: @prune) })
        rescue Git::Error => e
          failure(project, ERROR_WORDS.fetch(e.class, FAILED), REASONS.fetch(e.class) { State.for_error(e) }, e)
        end

        # A fetch refuses a branch that tracks a local one before it contacts any remote, so a dry
        # run can tell the same without fetching.
        def rehearse(project)
          raise Git::LocalUpstream, path(project) if @runtime.git.local_upstream?(path(project))

          outcome(project, FETCHED)
        end

        # An origin or an upstream settles it without a spawn; git is asked only when neither
        # exists, since it may still pick a sole remote.
        def remoteless?(project, inspection)
          inspection.remote.nil? && inspection.status.upstream.nil? && !@runtime.git.default_remote?(path(project))
        end

        def path(project) = Paths.expand(project.path, home: @runtime.paths.home)

        # Two fetches into one ref store race on its ref locks, and one of them fails.
        def exclusively(path, &)
          key = @runtime.git.common_dir(path)
          @guard.synchronize { @locks[key] }.synchronize(&)
        end

        # Git before 2.41 lists no refs, so a fetch that succeeded there reads as fetched.
        def fetched(project, result)
          updates = result.updates
          return outcome(project, FETCHED) if updates.nil?
          return outcome(project, UNCHANGED) if updates.empty?

          outcome(project, FETCHED, nil, refs(updates))
        end

        def outcome(project, word, reason = nil, details = []) = Outcome.new(project:, word:, reason:, details:)

        # The line above already names the project, so the path is cut from the message.
        def failure(project, word, reason, error)
          outcome(project, word, reason, [message(error), error.hint].compact)
        end

        # Nothing else in the result says which directory could not be read, so it leads the
        # detail, as the manifest writes it.
        def unreadable(project, inspection)
          error = inspection.error
          outcome(project, SKIPPED, inspection.state, ["#{project.path}: #{message(error)}", error.hint].compact)
        end

        def message(error) = error.message.delete_prefix("#{error.path}: ")

        def refs(updates)
          lines = updates.first(REF_LIMIT).map do |ref, old_id, new_id|
            ref_line(ref.sub(SHORT_REF, ''), old_id, new_id)
          end
          lines << "and #{updates.size - REF_LIMIT} more" if updates.size > REF_LIMIT
          lines
        end

        # Git writes the all-zero id for the old side of a new ref and the new side of a pruned one.
        def ref_line(name, old_id, new_id)
          return "#{name} #{new_id[0, ABBREV]} (new)" if ZERO_ID.match?(old_id)
          return "#{name} deleted (was #{old_id[0, ABBREV]})" if ZERO_ID.match?(new_id)

          "#{name} #{old_id[0, ABBREV]}..#{new_id[0, ABBREV]}"
        end

        # Ref names and messages come from git and the remote, so they are redacted and made plain.
        def report(outcome)
          word = outcome.word
          line = Base.result_text(@context, Resources::PROJECTS, outcome.project.name, word, ROLES.fetch(word),
                                  reason: outcome.reason, dry_run: @dry_run)
          details = outcome.details.map { INDENT + @context.paint(:muted, Output.plain(Git::Url.redact(it))) }
          @context.puts(line, *details)
        end

        def summarize(count)
          counts = ROLES.keys.filter_map { "#{@tally[it]} #{it}" if @tally.key?(it) }
          line = "#{count} projects: #{counts.join(', ')}"
          line += " #{DRY_RUN}" if @dry_run
          @context.warn(@context.paint_err(:muted, line))
        end
      end

      private_constant :Session
    end
  end
end
