# frozen_string_literal: true

require_relative 'commands_helper'

# A project whose branch slipway fast-forwarded once, from OLD to CommandsHelper::SHA, as Git::Fake
# answers for it.
module RolloutHelper
  include CommandsHelper

  OLD = 'f0e1d2c3b4a5968778695a4b3c2d1e0f12345678'
  # Newest first, as git lists them: a clone at OLD, then slipway's fast-forward to SHA.
  SYNCED = [
    Slipway::Git::ReflogEntry.new(sha: SHA, time: Time.utc(2026, 9, 29, 11), subject: 'slipway sync: Fast-forward'),
    Slipway::Git::ReflogEntry.new(sha: OLD, time: Time.utc(2026, 9, 28, 9), subject: 'clone: from /srv/hldr.git')
  ].freeze
  # How far HEAD is from OLD: one commit ahead, which a move back drops.
  BACK = Slipway::Git::Distance.new(ahead: 1, behind: 0)

  def run_rollout(*, runtime:) = run_commands('rollout', *, runtime:, commands: [Slipway::Commands::Rollout])
end
