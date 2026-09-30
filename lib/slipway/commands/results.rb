# frozen_string_literal: true

require_relative 'base'
require_relative '../git'
require_relative '../output'
require_relative '../pool'

module Slipway
  module Commands
    # The lines of a verb that acts on each selected repository: one result per project, its
    # details below it, and a count of the results on stderr once more than one project ran.
    class Results
      INDENT = '  '
      DRY_RUN = '(dry run)'

      # `roles` maps each result word to its theme role, in the order the count lists them.
      def initialize(context, roles, dry_run:)
        @context = context
        @roles = roles
        @dry_run = dry_run
        @tally = Hash.new(0)
      end

      # Runs `work` for each project on a pool of `workers` and prints each outcome, or what the
      # block turns it into on the calling thread, in the order the projects are listed.
      # Ruby buffers a stdout that is not a terminal: a pipe would see the lines only at exit,
      # after the count on stderr, and since Ruby flushes stdout before it spawns, a line a
      # closed pipe refused would stay in the buffer and fail every later git with EPIPE.
      def stream(projects, workers:, work:)
        @context.unbuffer
        Pool.new(workers:).each_ordered(projects, work) { report(block_given? ? yield(it) : it) }
      end

      def any?(*words) = words.any? { @tally.key?(it) }

      def summarize
        count = @tally.values.sum
        return if count < 2

        counts = @roles.keys.filter_map { "#{@tally[it]} #{it}" if @tally.key?(it) }
        line = "#{count} projects: #{counts.join(', ')}"
        line += " #{DRY_RUN}" if @dry_run
        @context.warn(@context.paint_err(:muted, line))
      end

      # Ref names and messages come from git and the remote, so they are redacted and made plain.
      def report(outcome)
        word = outcome.word
        @tally[word] += 1
        line = Base.result_text(@context, Resources::PROJECTS, outcome.project.name, word, @roles.fetch(word),
                                reason: outcome.reason, dry_run: @dry_run)
        details = outcome.details.map { INDENT + @context.paint(:muted, Output.plain(Git::Url.redact(it))) }
        @context.puts(line, *details)
      end
    end
  end
end
