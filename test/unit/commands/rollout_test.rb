# frozen_string_literal: true

require 'test_helper'

# rollout history, unpin, pause and resume: the history read from the branch reflog, and the spec
# fields the others write without running git.
class RolloutTest < Minitest::Test
  include RolloutHelper

  UNDONE = [Slipway::Git::ReflogEntry.new(sha: OLD, time: Time.utc(2026, 9, 29, 12),
                                          subject: 'slipway rollout undo: updating HEAD'), *SYNCED].freeze

  def test_history_lists_the_revisions_oldest_first_with_the_cause_of_each_move
    with_runtime do |runtime|
      register(runtime, 'hldr', reflog: SYNCED, between: 3)

      assert_equal [0, <<~TEXT, ''], run_rollout('history', 'hldr', runtime:)
        REVISION   COMMIT    DATE                   CHANGE-CAUSE                   PINNED
        1          f0e1d2c   2026-09-28T09:00:00Z   <none>                         false
        2          a1b2c3d   2026-09-29T11:00:00Z   sync: fast-forward 3 commits   false
      TEXT
      assert_equal [:commits_between, { from: OLD, to: SHA }],
                   runtime.git.calls.find { it.first == :commits_between }.values_at(0, 2)
    end
  end

  def test_history_names_the_revision_an_undo_returned_to_and_marks_the_pinned_one
    with_runtime do |runtime|
      register(runtime, 'hldr', commit: COMMIT.with(sha: OLD), reflog: UNDONE, between: 1, spec: { revision: OLD })

      assert_equal [0, <<~TEXT, ''], run_rollout('history', 'project/hldr', runtime:)
        REVISION   COMMIT    DATE                   CHANGE-CAUSE                  PINNED
        1          f0e1d2c   2026-09-28T09:00:00Z   <none>                        false
        2          a1b2c3d   2026-09-29T11:00:00Z   sync: fast-forward 1 commit   false
        3          f0e1d2c   2026-09-29T12:00:00Z   rollout undo to revision 1    true
      TEXT
    end
  end

  # Git expired the entry the first move started from, so nothing says how far that move went.
  def test_history_leaves_the_count_out_when_the_log_lacks_where_the_move_started
    with_runtime do |runtime|
      register(runtime, 'hldr', reflog: SYNCED.first(1))

      assert_includes run_rollout('history', 'hldr', runtime:)[1], "   sync: fast-forward   false\n"
    end
  end

  def test_history_without_slipway_moves_prints_a_notice_on_stderr_and_succeeds
    with_runtime do |runtime|
      register(runtime, 'hldr')

      assert_equal [0, '', "No rollout history found for project/hldr.\n"], run_rollout('history', 'hldr', runtime:)
    end
  end

  def test_history_of_a_detached_head_or_an_unreadable_project_is_an_error
    with_runtime do |runtime|
      register(runtime, 'loose', status: DETACHED)
      register(runtime, 'gone', status: nil)

      status, out, err = run_rollout('history', 'loose', runtime:)

      assert_equal [1, ''], [status, out]
      assert_includes err, 'project/loose: HEAD is detached at a1b2c3d; rollout history reads the reflog of the ' \
                           'checked-out branch'
      assert_equal 1, run_rollout('history', 'gone', runtime:).first
    end
  end

  def test_history_takes_exactly_one_project
    with_runtime do |runtime|
      register(runtime, 'hldr')

      assert_equal 2, run_rollout('history', runtime:).first
      assert_equal 2, run_rollout('history', 'hldr', 'hldr', runtime:).first
    end
  end

  def test_unpin_removes_only_spec_revision_and_says_when_there_was_none
    with_runtime do |runtime|
      register(runtime, 'hldr', spec: { revision: OLD, branch: 'main' })
      register(runtime, 'free')

      assert_equal [0, "project/hldr unpinned\nproject/free not pinned\n", ''],
                   run_rollout('unpin', 'hldr', 'free', runtime:)
      assert_equal [nil, 'main'], [project(runtime, 'hldr').revision, project(runtime, 'hldr').branch]
      assert_empty runtime.git.calls
    end
  end

  def test_pause_and_resume_write_only_spec_paused
    with_runtime do |runtime|
      register(runtime, 'dots', spec: { revision: OLD })
      before = project(runtime, 'dots')

      assert_equal [0, "project/dots paused\n", ''], run_rollout('pause', 'dots', runtime:)
      assert_equal before.with(paused: true), project(runtime, 'dots')
      assert_equal [0, "project/dots already paused\n", ''], run_rollout('pause', 'dots', runtime:)
      assert_equal [0, "project/dots resumed\n", ''], run_rollout('resume', 'dots', runtime:)
      assert_equal [before, "project/dots not paused\n"],
                   [project(runtime, 'dots'), run_rollout('resume', 'dots', runtime:)[1]]
      assert_empty runtime.git.calls
    end
  end

  def test_the_spec_verbs_need_a_name_and_refuse_an_unknown_one
    with_runtime do |runtime|
      %w[unpin pause resume].each do |verb|
        assert_equal 2, run_rollout(verb, runtime:).first, verb
        assert_equal [1, ''], run_rollout(verb, 'ghost', runtime:).first(2), verb
      end
    end
  end

  private

  def project(runtime, name) = runtime.store.find(Slipway::Resources::PROJECTS, name, group: 'default')
end
