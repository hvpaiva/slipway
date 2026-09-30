# frozen_string_literal: true

require 'test_helper'

# How the checked-out branch follows its upstream: the fast-forward, what blocks it, and the
# policies that hold a project still.
class PlanTest < Minitest::Test
  include PlanHelper

  STATUS = 'git -C ~/dev/hldr status'

  def test_a_clean_or_ahead_repository_has_converged
    assert_predicate plan, :converged?
    assert_predicate plan(CLEAN.with(ahead: 2)), :converged?
    assert_predicate plan(CLEAN.with(untracked: 4, stashes: 1)), :converged?
  end

  def test_a_clean_branch_behind_its_upstream_is_fast_forwarded
    three = plan(BEHIND)
    one = plan(CLEAN.with(behind: 1, untracked: 2))

    assert_equal [[%w[Behind], [], []], [['Behind', '3 commits behind origin/main; sync will fast-forward']]],
                 [kinds(three), lines(three)]
    assert_equal [['Behind', '1 commit behind origin/main; sync will fast-forward']], lines(one)
    assert_predicate one, :fast_forward?
  end

  def test_local_changes_block_the_fast_forward_and_leave_the_drift_reported
    both = plan(BEHIND.with(staged: 2, unstaged: 1))
    unstaged = plan(BEHIND.with(unstaged: 1))

    assert_equal [[], %w[Dirty], %w[Behind]], kinds(both)
    assert_equal [['Behind', '3 commits behind origin/main'],
                  ['Dirty', '2 staged, 1 unstaged; sync fast-forwards only a tree without staged or unstaged changes',
                   STATUS]], lines(both)
    assert_equal '1 unstaged; sync fast-forwards only a tree without staged or unstaged changes',
                 unstaged.skips.first.message
    refute_predicate both, :fast_forward?
  end

  def test_a_conflict_outranks_local_changes_and_local_commits
    conflicted = plan(BEHIND.with(conflicted: 1, unstaged: 2, ahead: 1))

    assert_equal [['Behind', '3 commits behind origin/main'],
                  ['Conflicted', '1 unmerged path; finish or abort the merge first', STATUS]], lines(conflicted)
    assert_equal '2 unmerged paths; finish or abort the merge first',
                 plan(BEHIND.with(conflicted: 2)).skips.first.message
  end

  def test_a_diverged_branch_is_never_merged
    diverged = plan(BEHIND.with(ahead: 2, behind: 5))

    assert_equal [['Behind', '5 commits behind origin/main'],
                  ['Diverged', '2 ahead, 5 behind origin/main; sync never merges or rebases',
                   'git -C ~/dev/hldr log --oneline --left-right HEAD...@{upstream}']], lines(diverged)
  end

  def test_an_operation_in_progress_blocks_a_fast_forward_and_is_asked_only_then
    rebasing = plan(BEHIND, operation: 'rebase')
    merged = plan(CLEAN, operation: 'merge')

    assert_equal [['Behind', '3 commits behind origin/main'], ['InProgress', 'a rebase is in progress', STATUS]],
                 lines(rebasing)
    assert_predicate merged, :converged?
  end

  def test_a_branch_that_follows_no_live_upstream_cannot_be_moved
    detached = plan(CommandsHelper::DETACHED)
    unborn = plan(CommandsHelper::UNBORN, commit: nil)
    gone = plan(CLEAN.with(branch: 'feature', upstream: 'origin/feature', ahead: nil, behind: nil, upstream_gone: true))

    assert_equal [[], %w[Detached], []], kinds(detached)
    assert_equal [['Detached', 'HEAD is detached at a1b2c3d; sync never moves a detached HEAD', STATUS]],
                 lines(detached)
    assert_equal [['Unborn', 'no commits yet; nothing to fast-forward']], lines(unborn)
    assert_equal [['Gone', 'upstream origin/feature no longer exists; sync never retargets a branch',
                   'git -C ~/dev/hldr branch -vv']], lines(gone)
  end

  def test_a_branch_without_upstream_is_offered_origin_only_when_origin_exists_and_the_name_is_plain
    untracked = CLEAN.with(upstream: nil, ahead: nil, behind: nil)
    offered = plan(untracked, origin: 'git@forge.test:o/hldr.git')
    alone = plan(untracked)
    odd = plan(untracked.with(branch: 'x$(id)'), origin: 'git@forge.test:o/hldr.git')

    assert_equal [['NoUpstream', 'main tracks no upstream; sync fast-forwards only a tracking branch',
                   'git -C ~/dev/hldr branch --set-upstream-to=origin/main']], lines(offered)
    assert_nil alone.skips.first.command
    assert_equal ['NoUpstream', 'x$(id) tracks no upstream; sync fast-forwards only a tracking branch'],
                 lines(odd).first
  end

  def test_fetch_only_reports_the_upstream_and_nothing_blocks_it
    behind = plan(BEHIND.with(staged: 1), sync_policy: 'FetchOnly')

    assert_equal [[], [], %w[Behind]], kinds(behind)
    assert_equal [['Behind', '3 commits behind origin/main; syncPolicy is FetchOnly']], lines(behind)
    assert_predicate plan(CommandsHelper::DETACHED, sync_policy: 'FetchOnly'), :converged?
  end

  def test_a_paused_project_is_reported_and_never_moved_whatever_its_policy
    paused = plan(BEHIND.with(unstaged: 1), paused: true, sync_policy: 'FetchOnly')

    assert_equal [['Behind', '3 commits behind origin/main; the project is paused']], lines(paused)
    assert_predicate plan(CommandsHelper::UNBORN, commit: nil, paused: true), :converged?
    refute_predicate paused, :fast_forward?
  end
end
