# frozen_string_literal: true

require 'test_helper'

# rollout undo on repositories Git::Fake describes: the move, the pin written after it, and every
# refusal, each of which leaves the branch and the manifest alone.
class RolloutUndoTest < Minitest::Test
  include RolloutHelper

  ENTRY = Slipway::Git::ReflogEntry
  MOVED_BACK = Slipway::Git::MoveBack.new(from: SHA, to: OLD, count: 1)
  ROLLED_BACK = <<~TEXT
    project/hldr rolled back
      main a1b2c3d..f0e1d2c (1 commit back to revision 1); held there by spec.revision
      'slipway rollout unpin project/hldr' follows origin/main again
  TEXT
  READS = %i[status last_commit remote_url fetched_at in_progress reflog distance].freeze

  def test_the_branch_moves_back_to_the_previous_revision_and_the_manifest_then_pins_it
    with_runtime do |runtime|
      register(runtime, 'hldr', reflog: SYNCED, distance: BACK, roll_back: MOVED_BACK)

      assert_equal [0, ROLLED_BACK, ''], run_undo('hldr', runtime:)
      assert_equal OLD, pin(runtime)
      assert_equal [:roll_back, { to: OLD, reflog_action: 'slipway rollout undo' }],
                   runtime.git.calls.find { it.first == :roll_back }.values_at(0, 2)
    end
  end

  def test_unstaged_and_untracked_changes_leave_a_move_back_to_git
    with_runtime do |runtime|
      status = CLEAN.with(unstaged: 2, untracked: 1)
      register(runtime, 'hldr', status:, reflog: SYNCED, distance: BACK, roll_back: MOVED_BACK)

      assert_equal [0, ROLLED_BACK, ''], run_undo('hldr', runtime:)
      assert_equal OLD, pin(runtime)
    end
  end

  def test_a_dry_run_prints_the_same_lines_and_only_reads
    with_runtime do |runtime|
      register(runtime, 'hldr', reflog: SYNCED, distance: BACK, roll_back: MOVED_BACK)

      assert_equal [0, ROLLED_BACK.sub("back\n", "back (dry run)\n"), ''],
                   run_undo('hldr', '--dry-run', runtime:)
      assert_nil pin(runtime)
      assert_empty(runtime.git.calls.map(&:first).uniq - READS)
    end
  end

  # Revision 3 is the undo back to OLD; revision 2 is where the branch stood before it.
  def test_to_revision_moves_forward_with_a_fast_forward_that_names_the_undo
    with_runtime do |runtime|
      undone = [ENTRY.new(sha: OLD, time: Time.utc(2026, 9, 29, 12), subject: 'slipway rollout undo: updating HEAD'),
                *SYNCED]
      forward = Slipway::Git::FastForward.new(from: OLD, to: SHA, count: 1)
      register(runtime, 'hldr', commit: COMMIT.with(sha: OLD, short: OLD[0, 7]), reflog: undone,
                                distance: Slipway::Git::Distance.new(ahead: 0, behind: 1, off_upstream: 0),
                                fast_forward: forward, spec: { revision: OLD })

      assert_equal [0, <<~TEXT, ''], run_undo('hldr', '--to-revision=2', '-n', 'default', runtime:)
        project/hldr rolled back
          main f0e1d2c..a1b2c3d (1 commit forward to revision 2); held there by spec.revision
          'slipway rollout unpin project/hldr -n default' follows origin/main again
      TEXT
      assert_equal({ onto: SHA, reflog_action: 'slipway rollout undo' },
                   runtime.git.calls.find { it.first == :fast_forward }.last)
      assert_equal SHA, pin(runtime)
    end
  end

  def test_a_branch_already_at_the_pinned_revision_is_unchanged
    with_runtime do |runtime|
      register(runtime, 'hldr', reflog: SYNCED, distance: Slipway::Git::Distance.new(ahead: 0, behind: 0),
                                spec: { revision: SHA })

      assert_equal [0, <<~TEXT, ''], run_undo('hldr', '--to-revision=2', runtime:)
        project/hldr unchanged
          main is already at a1b2c3d (revision 2); held there by spec.revision
          'slipway rollout unpin project/hldr' follows origin/main again
      TEXT
      refute(runtime.git.calls.any? { %i[roll_back fast_forward].include?(it.first) })
    end
  end

  def test_git_refusing_the_move_is_relayed_and_nothing_is_pinned
    { Slipway::Git::WouldLoseChanges => "(WouldLoseChanges)\n  the move would overwrite local changes; commit " \
                                        "or move them and run undo again\n  git -C ~/dev/hldr status\n",
      Slipway::Git::WouldOverwrite => "(WouldOverwrite)\n  the move would overwrite untracked or ignored files; " \
                                      "move them and run undo again\n  git -C ~/dev/hldr status --ignored\n",
      Slipway::Git::Busy => "(Busy)\n  another git process holds index.lock, or one left it behind; undo never " \
                            "removes a lock\n",
      Slipway::Git::Error => "(Unknown)\n  git command failed\n" }.each do |error, text|
      with_runtime do |runtime|
        register(runtime, 'hldr', reflog: SYNCED, distance: BACK, roll_back: error)
        word = error == Slipway::Git::Error ? 'failed' : 'skipped'

        assert_equal [1, "project/hldr #{word} #{text}", ''], run_undo('hldr', runtime:), error.name
        assert_nil pin(runtime)
      end
    end
  end

  # The branch has moved when the manifest write fails; running the command the line names only
  # writes the pin, instead of an undo of the undo moving the branch forward again.
  def test_a_manifest_that_cannot_be_written_after_the_move_names_the_command_that_holds_it
    with_runtime do |runtime|
      register(runtime, 'hldr', reflog: SYNCED, distance: BACK, roll_back: MOVED_BACK)
      failing_save(runtime)

      assert_equal [1, <<~TEXT, ''], run_undo('hldr', runtime:)
        project/hldr failed (NotPinned)
          main a1b2c3d..f0e1d2c (1 commit back to revision 1)
          spec.revision was not written: no space left; run 'slipway rollout undo project/hldr --to-revision=1' to hold it there
      TEXT
      assert_nil pin(runtime)
    end
  end

  def test_the_named_command_after_a_failed_write_moves_nothing_and_writes_the_pin
    with_runtime do |runtime|
      undone = [ENTRY.new(sha: OLD, time: Time.utc(2026, 9, 29, 12), subject: 'slipway rollout undo: updating HEAD'),
                *SYNCED]
      register(runtime, 'hldr', commit: COMMIT.with(sha: OLD, short: OLD[0, 7]), reflog: undone,
                                distance: Slipway::Git::Distance.new(ahead: 0, behind: 0))

      assert_equal 0, run_undo('hldr', '--to-revision=1', runtime:).first
      assert_equal OLD, pin(runtime)
      refute(runtime.git.calls.any? { %i[roll_back fast_forward].include?(it.first) })
    end
  end

  def test_a_negative_or_non_numeric_revision_is_a_usage_error
    with_runtime do |runtime|
      register(runtime, 'hldr')

      %w[-1 two 1.5].each do |value|
        status, out, err = run_undo('hldr', "--to-revision=#{value}", runtime:)

        assert_equal [2, ''], [status, out], value
        assert_includes err, "invalid argument #{value.inspect} for --to-revision", value
      end
    end
  end

  def test_a_project_whose_directory_is_missing_is_skipped
    with_runtime do |runtime|
      register(runtime, 'gone', status: nil)

      assert_equal [1, "project/gone skipped (Missing)\n  ~/dev/gone: no such directory\n", ''],
                   run_undo('gone', runtime:)
    end
  end

  private

  def pin(runtime) = runtime.store.find(Slipway::Resources::PROJECTS, 'hldr', group: 'default').revision

  def failing_save(runtime)
    runtime.store.define_singleton_method(:save) { |_resource| raise Slipway::Error, 'no space left' }
  end

  def run_undo(*, runtime:) = run_rollout('undo', *, runtime:)
end
