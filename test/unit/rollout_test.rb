# frozen_string_literal: true

require 'test_helper'

# The revisions of a branch, numbered from the moves slipway left in its reflog.
class RolloutHistoryTest < Minitest::Test
  A = 'a' * 40
  B = 'b' * 40
  C = 'c' * 40
  D = 'd' * 40

  def test_a_sync_after_a_clone_makes_the_clone_the_first_revision_and_the_sync_the_second
    history = history([A, 'clone: from /srv/x.git'], [B, 'slipway sync: Fast-forward'])

    assert_equal [[1, A, nil, nil], [2, B, 'sync', A]], summary(history)
    assert_equal history.revisions.first, history.previous(B)
    assert_equal history.revisions.last, history.previous(C)
  end

  def test_an_undo_is_a_revision_of_its_own_and_names_the_revision_it_returned_to
    history = history([A, 'clone: from /srv/x.git'], [B, 'slipway sync: Fast-forward'],
                      [A, 'slipway rollout undo: updating HEAD'], [B, 'slipway rollout undo: Fast-forward'])
    third, fourth = history.revisions.last(2)

    assert_equal [[3, A, 'rollout undo', B], [4, B, 'rollout undo', A]], summary(history).last(2)
    assert_equal [1, 2], [history.undone_to(third).number, history.undone_to(fourth).number]
    assert_equal [fourth, third], [history.pinned(B), history.pinned(A)]
    assert_nil history.pinned(C)
  end

  # The user's own commit between two syncs is where the second one started.
  def test_a_move_slipway_did_not_make_is_a_revision_only_when_slipway_moved_on_from_it
    history = history([A, 'commit (initial): first'], [B, 'commit: second'], [C, 'slipway sync: Fast-forward'],
                      [D, 'commit: mine'])

    assert_equal [[1, B, nil, nil], [2, C, 'sync', B]], summary(history)
    assert_equal history.revisions.last, history.previous(D)
  end

  def test_a_log_without_slipway_moves_has_no_revisions
    history = history([A, 'commit (initial): first'], [B, 'pull: Fast-forward'])

    assert_predicate history, :empty?
    assert_nil history.previous(B)
    assert_nil history.revision(1)
  end

  def test_a_log_git_cut_at_a_slipway_move_starts_at_that_move
    history = history([B, 'slipway sync: Fast-forward'])

    assert_equal [[1, B, 'sync', nil]], summary(history)
    assert_nil history.previous(B)
  end

  def test_the_command_names_the_group_only_when_it_is_not_the_selected_one
    project = Slipway::Project.new(name: 'api', group: 'work', path: '~/dev/api')

    assert_equal ['slipway rollout undo project/api', 'slipway rollout unpin project/api -n work'],
                 [Slipway::Rollout.command('undo', project, 'work'), Slipway::Rollout.command('unpin', project, nil)]
  end

  private

  # +moves+ are [sha, subject] pairs, oldest first; git lists them newest first.
  def history(*moves)
    entries = moves.each_with_index.map do |(sha, subject), index|
      Slipway::Git::ReflogEntry.new(sha:, time: Time.at(1_727_000_000 + index).utc, subject:)
    end
    Slipway::Rollout::History.new(entries.reverse)
  end

  def summary(history) = history.revisions.map { [it.number, it.sha, it.action, it.from] }
end
