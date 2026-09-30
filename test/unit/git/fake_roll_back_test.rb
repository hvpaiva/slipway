# frozen_string_literal: true

require 'test_helper'
require 'slipway/git'

class GitFakeRollBackTest < Minitest::Test
  CURRENT = Slipway::Git::Status.new(head: 'bbbbbbb', branch: 'main', upstream: 'origin/main', ahead: 0, behind: 0)
  BACK = Slipway::Git::MoveBack.new(from: 'b' * 40, to: 'a' * 40, count: 2)
  ENTRY = Slipway::Git::ReflogEntry.new(sha: 'b' * 40, time: Time.at(0).utc, subject: 'slipway sync: Fast-forward')

  def setup
    @fake = Slipway::Git::Fake.new
  end

  def test_a_move_back_happens_once_and_leaves_the_branch_that_many_commits_behind
    @fake.add('/srv/hldr', status: CURRENT, commit: CommandsHelper::COMMIT, roll_back: BACK)

    assert_same BACK, @fake.roll_back('/srv/hldr', to: 'a' * 40)
    assert_equal [CURRENT.with(head: 'aaaaaaa', behind: 2), 'a' * 40],
                 [@fake.status('/srv/hldr'), @fake.last_commit('/srv/hldr').sha]
    refute_predicate @fake.roll_back('/srv/hldr', to: 'a' * 40), :moved?
    assert_equal [:roll_back, '/srv/hldr', { to: 'a' * 40, reflog_action: 'slipway rollout undo' }], @fake.calls.last
  end

  def test_a_canned_refusal_is_raised_and_moves_nothing
    @fake.add('/srv/hldr', status: CURRENT, roll_back: Slipway::Git::WouldLoseChanges)

    assert_raises(Slipway::Git::WouldLoseChanges) { @fake.roll_back('/srv/hldr', to: 'a' * 40) }
    assert_equal CURRENT, @fake.status('/srv/hldr')
  end

  def test_the_reflog_and_the_count_between_commits_are_answered_as_given
    @fake.add('/srv/hldr', status: CURRENT, reflog: [ENTRY], between: 3)

    assert_equal [[ENTRY], 3], [@fake.reflog('/srv/hldr', 'main'), @fake.commits_between('/srv/hldr', 'a', 'b')]
    assert_empty Slipway::Git::Fake.new.add('/srv/x', status: CURRENT).reflog('/srv/x', 'main')
  end
end
