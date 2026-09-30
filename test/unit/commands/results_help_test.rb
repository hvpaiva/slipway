# frozen_string_literal: true

require 'test_helper'

# The Results section of fetch, sync and rollout undo is the only place their man pages explain
# a result line, so it names every word the verb prints and every reason it gives.
class ResultsHelpTest < Minitest::Test
  UNREADABLE = [Slipway::Git::MissingPath, Slipway::Git::NotARepository, Slipway::Git::UnsafeRepository,
                Slipway::Git::Error].map { Slipway::State.for_error(it.allocate) }.freeze
  FETCH = [*Slipway::Outcome::REASONS.values, Slipway::Fetcher::NO_REMOTE, *UNREADABLE].uniq.freeze
  SYNC = [*FETCH, *Slipway::Syncer::ADVICE.keys].freeze
  UNDO = [*UNREADABLE, *Slipway::Rollback::REFUSALS.keys, *Slipway::Rollback::RELAYED.keys, 'Busy',
          Slipway::Rollback::NOT_PINNED, 'AuthRequired', 'Timeout'].uniq.freeze
  REASON = ' (Reason)'

  def test_fetch_explains_every_result_and_reason
    assert_explains Slipway::Commands::Fetch, FETCH
  end

  def test_sync_explains_every_result_and_reason
    assert_explains Slipway::Commands::SyncCommand, SYNC
  end

  def test_rollout_undo_explains_every_result_and_reason
    assert_explains Slipway::Commands::RolloutCommand::Undo, UNDO
  end

  private

  def assert_explains(verb, reasons)
    entries = verb::RESULTS.entries
    text = entries.values.join(' ')

    assert_equal(verb::ROLES.keys, entries.keys.map { it.delete_suffix(REASON) })
    reasons.each { assert_match(/\b#{it}\b/, text, "#{verb} does not explain #{it}") }
  end
end
