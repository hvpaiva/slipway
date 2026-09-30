# frozen_string_literal: true

require_relative 'git'
require_relative 'paths'
require_relative 'state'

module Slipway
  # Fetches one project and names the outcome in the words the verbs that fetch share. Several
  # workers call it at once.
  class Fetcher
    # `details` are printed under the result line as they are; the printer redacts them and
    # makes them plain. The verbs that move a branch name their failures in the same words.
    Outcome = Data.define(:project, :word, :reason, :details) do
      def initialize(project:, word:, reason: nil, details: []) = super

      # The line above already names the project, so the path is cut from the message.
      def self.failure(project, error)
        reason = REASONS.fetch(error.class) { State.for_error(error) }
        new(project:, word: ERROR_WORDS.fetch(error.class, FAILED), reason:,
            details: [detail(error), error.hint].compact)
      end

      # Nothing else in the result says which directory could not be read, so it leads the
      # detail, as the manifest writes it.
      def self.unreadable(project, inspection)
        error = inspection.error
        new(project:, word: SKIPPED, reason: inspection.state,
            details: ["#{project.path}: #{detail(error)}", error.hint].compact)
      end

      def self.detail(error) = error.message.delete_prefix("#{error.path}: ")
      private_class_method :detail
    end

    FETCHED = 'fetched'
    UNCHANGED = 'unchanged'
    SKIPPED = 'skipped'
    PAUSED = 'paused'
    DENIED = 'denied'
    FAILED = 'failed'
    # With no remote to pick, git fetch exits 0 and prints nothing, which would read as unchanged.
    NO_REMOTE = 'NoRemote'
    NO_REMOTE_DETAIL = 'no upstream, no origin and no single remote to fetch from'
    ERROR_WORDS = { Git::AuthRequired => DENIED, Git::LocalUpstream => SKIPPED }.freeze
    REASONS = { Git::AuthRequired => 'AuthRequired', Git::LocalUpstream => 'LocalUpstream',
                Git::Timeout => 'Timeout', Git::WriteTimeout => 'Timeout',
                Git::ProtocolNotAllowed => 'ProtocolNotAllowed' }.freeze
    REF_LIMIT = 5
    ABBREV = Git::Porcelain::ABBREVIATION
    ZERO_ID = /\A0+\z/
    SHORT_REF = %r{\Arefs/(?:remotes|tags|heads)/}

    def initialize(runtime, prune:, dry_run:)
      @runtime = runtime
      @prune = prune
      @dry_run = dry_run
      @locks = Hash.new { |locks, key| locks[key] = Mutex.new }
      @guard = Mutex.new
    end

    # The whole of the fetch verb for one project.
    def attempt(project)
      return Outcome.new(project:, word: PAUSED) if project.paused

      inspection = @runtime.inspector.examine(project)
      return Outcome.unreadable(project, inspection) if inspection.error

      fetch(project, inspection)
    end

    # `inspection` is the project's, read without an error. An error git reports becomes the
    # outcome; anything else is a bug and leaves through the caller.
    def fetch(project, inspection)
      return no_remote(project) if remoteless?(inspection)
      return rehearse(project) if @dry_run

      fetched(project, exclusively(project) { @runtime.git.fetch(path(project), prune: @prune) })
    rescue Git::Error => e
      Outcome.failure(project, e)
    end

    # Two writes into one ref store race on its ref locks, and one of them fails.
    def exclusively(project, &)
      key = @runtime.git.common_dir(path(project))
      @guard.synchronize { @locks[key] }.synchronize(&)
    end

    def path(project) = Paths.expand(project.path, home: @runtime.paths.home)

    private

    # A fetch refuses a branch that tracks a local one before it contacts any remote, so a dry
    # run can tell the same without fetching.
    def rehearse(project)
      raise Git::LocalUpstream, path(project) if @runtime.git.local_upstream?(path(project))

      Outcome.new(project:, word: FETCHED)
    end

    # An origin or an upstream settles it without a spawn; git is asked only when neither
    # exists, since it may still pick a sole remote.
    def remoteless?(inspection)
      inspection.remote.nil? && inspection.status.upstream.nil? &&
        !@runtime.git.default_remote?(path(inspection.project))
    end

    def no_remote(project) = Outcome.new(project:, word: SKIPPED, reason: NO_REMOTE, details: [NO_REMOTE_DETAIL])

    # Git before 2.41 lists no refs, so a fetch that succeeded there reads as fetched.
    def fetched(project, result)
      updates = result.updates
      return Outcome.new(project:, word: FETCHED) if updates.nil?
      return Outcome.new(project:, word: UNCHANGED) if updates.empty?

      Outcome.new(project:, word: FETCHED, details: refs(updates))
    end

    def refs(updates)
      lines = updates.first(REF_LIMIT).map { |ref, old_id, new_id| ref_line(ref.sub(SHORT_REF, ''), old_id, new_id) }
      lines << "and #{updates.size - REF_LIMIT} more" if updates.size > REF_LIMIT
      lines
    end

    # Git writes the all-zero id for the old side of a new ref and the new side of a pruned one.
    def ref_line(name, old_id, new_id)
      return "#{name} #{new_id[0, ABBREV]} (new)" if ZERO_ID.match?(old_id)
      return "#{name} deleted (was #{old_id[0, ABBREV]})" if ZERO_ID.match?(new_id)

      "#{name} #{old_id[0, ABBREV]}..#{new_id[0, ABBREV]}"
    end
  end
end
