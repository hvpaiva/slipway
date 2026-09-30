# frozen_string_literal: true

require 'test_helper'

# A project pinned by spec.revision: sync may fast-forward the branch up to the pin, never past
# it and never back to it.
class PlanPinnedTest < Minitest::Test
  include PlanHelper

  PIN = 'b2c3d4e5f60718293a4b5c6d7e8f9012345678a1'
  AT = 'HEAD is at a1b2c3d, manifest pins b2c3d4e'
  STATUS = 'git -C ~/dev/hldr status'
  BEHIND_PIN = Slipway::Git::Distance.new(ahead: 0, behind: 2, off_upstream: 0)
  OFF_UPSTREAM = ['OffUpstream',
                  'spec.revision b2c3d4e is not on origin/main; sync moves a branch only along its upstream',
                  'git -C ~/dev/hldr log --oneline @{upstream}..b2c3d4e'].freeze

  def test_a_branch_at_the_pin_has_converged_whatever_its_upstream_and_tree
    assert_predicate plan(BEHIND.with(unstaged: 1, ahead: 1), revision: CommandsHelper::SHA), :converged?
    assert_predicate plan(CommandsHelper::DETACHED, revision: CommandsHelper::SHA), :converged?
  end

  # An annotated tag's own name differs from the commit HEAD is at, and git peels it to that commit.
  def test_a_pin_git_counts_no_commit_away_from_head_has_converged
    tag = plan(BEHIND, revision: PIN, pin: Slipway::Git::Distance.new(ahead: 0, behind: 0))

    assert_predicate tag, :converged?
  end

  def test_a_branch_behind_a_pin_its_upstream_holds_is_fast_forwarded_to_it
    result = plan(BEHIND, revision: PIN, pin: BEHIND_PIN)

    assert_equal [[%w[Revision], [], []], [['Revision', "#{AT}; sync will fast-forward"]]],
                 [kinds(result), lines(result)]
    assert_predicate result, :fast_forward?
    assert_predicate result, :to_revision?
    refute_predicate plan(BEHIND), :to_revision?
  end

  # A branch with commits its upstream lacks carries them to any pin that descends from it.
  def test_a_pin_its_upstream_lacks_or_was_not_compared_with_is_never_reached
    ahead = plan(CLEAN.with(ahead: 3), revision: PIN, pin: BEHIND_PIN.with(off_upstream: 3))
    side = plan(BEHIND, revision: PIN, pin: BEHIND_PIN.with(off_upstream: 1))
    unknown = plan(BEHIND, revision: PIN, pin: BEHIND_PIN.with(off_upstream: nil))

    assert_equal [['Revision', AT], OFF_UPSTREAM], lines(ahead)
    assert_equal([[[], %w[OffUpstream], %w[Revision]]] * 2, [side, unknown].map { kinds(it) })
    refute_predicate ahead, :fast_forward?
  end

  def test_a_pin_the_repository_lacks_is_not_found
    result = plan(BEHIND, revision: PIN)

    assert_equal [['Revision', AT],
                  ['RevisionNotFound', 'spec.revision b2c3d4e is not in this repository; fetch it or unpin']],
                 lines(result)
    refute_predicate result, :fast_forward?
  end

  def test_a_branch_past_the_pin_or_off_its_history_is_never_moved_back
    past = plan(CLEAN, revision: PIN, pin: Slipway::Git::Distance.new(ahead: 2, behind: 0))
    off = plan(CLEAN.with(branch: 'feature'), revision: PIN, pin: Slipway::Git::Distance.new(ahead: 1, behind: 1))

    assert_equal [['Revision', AT], ['PastRevision', 'main is past the pinned revision; sync never moves a branch back',
                                     'git -C ~/dev/hldr log --oneline b2c3d4e..HEAD']], lines(past)
    assert_equal 'feature is past the pinned revision; sync never moves a branch back', off.skips.first.message
  end

  def test_local_changes_and_an_operation_in_progress_block_the_move_to_the_pin
    dirty = plan(CLEAN.with(staged: 1), revision: PIN, pin: BEHIND_PIN)
    conflicted = plan(CLEAN.with(conflicted: 1, unstaged: 1), revision: PIN, pin: BEHIND_PIN)
    rebasing = plan(CLEAN, revision: PIN, pin: BEHIND_PIN, operation: 'rebase')

    assert_equal [[], %w[Dirty], %w[Revision]], kinds(dirty)
    assert_equal %w[Revision Conflicted], conflicted.items.map(&:type)
    assert_equal [['Revision', AT], ['InProgress', 'a rebase is in progress', STATUS]], lines(rebasing)
  end

  def test_a_branch_the_fast_forward_refuses_blocks_the_move_before_the_pin_is_looked_at
    detached = plan(CommandsHelper::DETACHED, revision: PIN, pin: BEHIND_PIN)
    unborn = plan(CommandsHelper::UNBORN, commit: nil, revision: PIN)
    untracking = plan(CLEAN.with(upstream: nil, ahead: nil, behind: nil), revision: PIN)

    assert_equal %w[Revision Detached], detached.items.map(&:type)
    assert_equal [['Revision', 'HEAD has no commits, manifest pins b2c3d4e'],
                  ['Unborn', 'no commits yet; nothing to fast-forward']], lines(unborn)
    assert_equal %w[Revision NoUpstream], untracking.items.map(&:type)
  end

  def test_a_held_project_reports_the_pin_and_nothing_blocks_it
    fetch_only = plan(CLEAN.with(staged: 1), revision: PIN, sync_policy: 'FetchOnly')
    paused = plan(CommandsHelper::DETACHED, revision: PIN, pin: BEHIND_PIN, paused: true)

    assert_equal [['Revision', "#{AT}; syncPolicy is FetchOnly"]], lines(fetch_only)
    assert_equal [[], [], %w[Revision]], kinds(paused)
    assert_equal "#{AT}; the project is paused", paused.reports.first.message
  end
end
