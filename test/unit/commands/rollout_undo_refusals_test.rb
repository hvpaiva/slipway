# frozen_string_literal: true

require 'test_helper'

# Each check rollout undo makes before it moves a branch: a fixed sentence, exit status 1, and
# neither the branch nor the manifest touched.
class RolloutUndoRefusalsTest < Minitest::Test
  include RolloutHelper

  FORWARD = Slipway::Git::Distance.new(ahead: 0, behind: 1, off_upstream: 0)

  def test_a_branch_that_is_conflicted_detached_or_unborn_is_refused
    assert_refused(
      'conflicted' => [{ status: CLEAN.with(conflicted: 2) },
                       "skipped (Conflicted)\n  2 unmerged paths; finish or abort the merge first\n  " \
                       "git -C ~/dev/conflicted status\n"],
      'detached' => [{ status: DETACHED },
                     "skipped (Detached)\n  HEAD is detached at a1b2c3d; undo moves only a checked-out branch\n  " \
                     "git -C ~/dev/detached status\n"],
      'unborn' => [{ status: UNBORN }, "skipped (Unborn)\n  no commits yet; nothing to roll back\n"]
    )
  end

  def test_a_branch_without_an_upstream_or_in_the_middle_of_an_operation_is_refused
    assert_refused(
      'lonely' => [{ status: CLEAN.with(upstream: nil, ahead: nil, behind: nil) },
                   "skipped (NoUpstream)\n  main tracks no upstream; undo drops only commits an upstream holds\n"],
      'gone' => [{ status: CLEAN.with(upstream_gone: true) },
                 "skipped (Gone)\n  upstream origin/main no longer exists; undo drops only commits an upstream " \
                 "holds\n  git -C ~/dev/gone branch -vv\n"],
      'busy' => [{ operation: 'rebase' },
                 "skipped (InProgress)\n  a rebase is in progress\n  git -C ~/dev/busy status\n"]
    )
  end

  def test_a_revision_the_history_lacks_or_the_repository_lacks_is_refused
    assert_refused(
      'fresh' => [{ reflog: [] }, "skipped (NoHistory)\n  no rollout history found for main\n"],
      'first' => [{ reflog: SYNCED.first(1) }, "skipped (NoPrevious)\n  no last revision to roll back to\n"],
      'blank' => [{ reflog: [], args: ['--to-revision=2'] },
                  "skipped (NoHistory)\n  no rollout history found for main\n"],
      'short' => [{ reflog: SYNCED, args: ['--to-revision=7'] },
                  "skipped (UnknownRevision)\n  unable to find specified revision 7 in history\n"],
      'pruned' => [{ reflog: SYNCED, distance: nil },
                   "skipped (RevisionNotFound)\n  commit f0e1d2c of revision 1 is not in this repository\n"]
    )
  end

  def test_a_move_that_would_drop_local_commits_or_leave_the_history_is_refused
    assert_refused(
      'local' => [{ status: CLEAN.with(ahead: 1), reflog: SYNCED, distance: BACK },
                  "skipped (LocalCommits)\n  main has commits that are not on origin/main; undo would drop them\n  " \
                  "git -C ~/dev/local log --oneline @{upstream}..HEAD\n"],
      'side' => [{ reflog: SYNCED, distance: Slipway::Git::Distance.new(ahead: 1, behind: 1) },
                 "skipped (Diverged)\n  revision 1 is not on the history of main; undo moves a branch only along it\n"]
    )
  end

  def test_a_move_back_refuses_staged_changes_and_lets_unstaged_ones_through_to_git
    assert_refused(
      'staged' => [{ status: DIRTY, reflog: SYNCED, distance: BACK },
                   "skipped (Dirty)\n  1 staged; undo moves a branch back only without staged changes, and " \
                   "forward only without staged or unstaged changes\n  git -C ~/dev/staged status\n"]
    )
  end

  def test_a_move_forward_needs_a_clean_tree_and_a_revision_on_the_upstream
    assert_refused(
      'dirty' => [{ status: DIRTY, reflog: SYNCED, distance: FORWARD },
                  "skipped (Dirty)\n  1 staged, 2 unstaged; undo moves a branch back only without staged " \
                  "changes, and forward only without staged or unstaged changes\n  git -C ~/dev/dirty status\n"],
      'off' => [{ reflog: SYNCED, distance: FORWARD.with(off_upstream: 1) },
                "skipped (OffUpstream)\n  revision 1 is not on origin/main; undo moves a branch forward only along " \
                "its upstream\n"]
    )
  end

  private

  def assert_refused(refusals)
    refusals.each do |name, (setup, text)|
      with_runtime do |runtime|
        args = setup.fetch(:args, [])
        register(runtime, name, roll_back: Slipway::Git::WouldLoseChanges, **setup.except(:args))
        run = run_rollout('undo', name, *args, runtime:)

        assert_equal [1, "project/#{name} #{text}", ''], run, name
        refute(runtime.git.calls.any? { %i[roll_back fast_forward].include?(it.first) }, name)
        assert_nil runtime.store.find(Slipway::Resources::PROJECTS, name, group: 'default').revision, name
      end
    end
  end
end
