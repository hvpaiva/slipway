# frozen_string_literal: true

require 'test_helper'
require 'slipway/git'

class GitFakeFastForwardTest < Minitest::Test
  BEHIND = Slipway::Git::Status.new(head: 'aaaaaaa', upstream: 'origin/main', ahead: 0, behind: 3)
  MOVE = Slipway::Git::FastForward.new(from: 'a' * 40, to: 'b' * 40, count: 2)
  UPSTREAM = Slipway::Git::Repository::UPSTREAM
  COMMIT = CommandsHelper::COMMIT.with(sha: 'a' * 40, short: 'aaaaaaa')

  def setup
    @fake = Slipway::Git::Fake.new
  end

  def test_a_move_happens_once_and_the_status_follows_it
    @fake.add('/srv/hldr', status: BEHIND, commit: COMMIT, fast_forward: MOVE)

    assert_same MOVE, @fake.fast_forward('/srv/hldr')
    assert_equal BEHIND.with(head: 'bbbbbbb', behind: 1), @fake.status('/srv/hldr')

    again = @fake.fast_forward('/srv/hldr')

    assert_equal Slipway::Git::FastForward.new(from: 'b' * 40, to: 'b' * 40, count: 0), again
    refute_predicate again, :moved?
    assert_equal 1, @fake.status('/srv/hldr').behind
  end

  def test_the_last_commit_follows_the_move
    @fake.add('/srv/hldr', status: BEHIND, commit: COMMIT, fast_forward: MOVE)

    @fake.fast_forward('/srv/hldr')

    assert_equal COMMIT.with(sha: 'b' * 40, short: 'bbbbbbb'), @fake.last_commit('/srv/hldr')
  end

  def test_by_default_a_fast_forward_moves_nothing_and_changes_nothing
    @fake.add('/srv/hldr', status: BEHIND, commit: COMMIT)

    move = @fake.fast_forward('/srv/hldr')

    assert_equal [COMMIT.sha, COMMIT.sha, 0], [move.from, move.to, move.count]
    assert_equal BEHIND, @fake.status('/srv/hldr')
  end

  def test_a_move_that_goes_nowhere_needs_the_last_commit_to_name_head
    @fake.add('/srv/hldr', status: BEHIND)

    assert_raises(ArgumentError) { @fake.fast_forward('/srv/hldr') }
  end

  def test_a_canned_refusal_is_raised_every_time_and_the_other_questions_still_answer
    dirty = Slipway::Git::Blocked.new('/srv/b', 'Dirty', '1 staged, 0 unstaged')
    @fake.add('/srv/a', status: BEHIND, fast_forward: Slipway::Git::Busy)
    @fake.add('/srv/b', status: BEHIND, fast_forward: dirty)

    2.times do
      error = assert_raises(Slipway::Git::Busy) { @fake.fast_forward('/srv/x/../a') }

      assert_equal '/srv/a', error.path
    end
    assert_same dirty, assert_raises(Slipway::Git::Blocked) { @fake.fast_forward('/srv/b') }
    assert_equal BEHIND, @fake.status('/srv/a')
  end

  def test_a_failing_or_unknown_path_raises_like_the_other_questions
    @fake.fail('/srv/plain', Slipway::Git::NotARepository)

    assert_raises(Slipway::Git::NotARepository) { @fake.fast_forward('/srv/plain') }
    assert_raises(Slipway::Git::MissingPath) { @fake.fast_forward('/srv/nothing') }
  end

  def test_calls_record_each_move_with_its_target_and_reflog_action
    @fake.add('/srv/hldr', status: BEHIND, commit: COMMIT)
    @fake.status('/srv/hldr')
    @fake.fast_forward('/srv/hldr/')
    @fake.fast_forward('/srv/hldr', onto: 'c' * 40, reflog_action: 'slipway rollout undo')

    assert_equal [[:status, '/srv/hldr'],
                  [:fast_forward, '/srv/hldr', { onto: UPSTREAM, reflog_action: 'slipway sync' }],
                  [:fast_forward, '/srv/hldr', { onto: 'c' * 40, reflog_action: 'slipway rollout undo' }]],
                 @fake.calls
  end
end
