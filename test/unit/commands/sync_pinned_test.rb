# frozen_string_literal: true

require 'test_helper'

# sync on a project pinned by spec.revision: up to the pin, never past it, never back to it.
class SyncPinnedTest < Minitest::Test
  include CommandsHelper

  PIN = 'b2c3d4e5f60718293a4b5c6d7e8f9012345678a1'
  BEHIND = CLEAN.with(behind: 3)
  TO_PIN = Slipway::Git::FastForward.new(from: SHA, to: PIN, count: 2)
  UNREACHABLE = <<~TEXT
    project/lost skipped (RevisionNotFound)
      spec.revision b2c3d4e is not in this repository; fetch it or unpin
    project/off skipped (OffUpstream)
      spec.revision b2c3d4e is not on origin/main; sync moves a branch only along its upstream
      git -C ~/dev/off log --oneline @{upstream}..b2c3d4e
    project/past skipped (PastRevision)
      main is past the pinned revision; sync never moves a branch back
      git -C ~/dev/past log --oneline b2c3d4e..HEAD
  TEXT

  def test_a_branch_behind_the_pin_moves_to_it_and_is_then_held_there
    with_runtime do |runtime|
      register(runtime, 'hldr', status: BEHIND, distance: distance(0, 2), fast_forward: TO_PIN, spec: { revision: PIN })

      assert_equal [0, "project/hldr fast-forwarded\n  main a1b2c3d..b2c3d4e (to the pinned revision)\n", ''],
                   run_sync(runtime:)
      assert_equal [0, "project/hldr unchanged\n  held at b2c3d4e by spec.revision\n", ''], run_sync(runtime:)
      assert_equal({ onto: PIN, reflog_action: 'slipway sync' },
                   runtime.git.calls.find { it.first == :fast_forward }.last)
    end
  end

  def test_a_branch_at_the_pin_is_held_whatever_its_upstream_brought
    with_runtime do |runtime|
      moved = Slipway::Git::FetchResult.new(updates: [['refs/remotes/origin/main', SHA, PIN]])
      register(runtime, 'hldr', status: BEHIND, fetch: moved, spec: { revision: SHA })
      held = "project/hldr unchanged\n  held at a1b2c3d by spec.revision\n"

      assert_equal [0, held, ''], run_sync(runtime:)
      assert_equal held.sub("\n", " (dry run)\n"), run_sync('--dry-run=client', runtime:)[1]
      refute(runtime.git.calls.any? { it.first == :fast_forward })
    end
  end

  # An annotated tag names another object than the commit it tags, and git counts none between them.
  def test_a_pin_git_counts_no_commit_away_from_head_is_held
    with_runtime do |runtime|
      register(runtime, 'hldr', status: BEHIND, distance: distance(0, 0), spec: { revision: PIN })

      assert_equal [0, "project/hldr unchanged\n  held at b2c3d4e by spec.revision\n", ''], run_sync(runtime:)
    end
  end

  def test_a_pin_the_repository_lacks_a_head_past_the_pin_and_a_pin_off_the_upstream_are_skipped
    with_runtime do |runtime|
      register(runtime, 'lost', spec: { revision: PIN })
      register(runtime, 'off', status: BEHIND, distance: distance(0, 2).with(off_upstream: 1), fast_forward: TO_PIN,
                               spec: { revision: PIN })
      register(runtime, 'past', distance: distance(2, 0), spec: { revision: PIN })

      assert_equal [0, UNREACHABLE, "3 projects: 3 skipped\n"], run_sync(runtime:)
      refute(runtime.git.calls.any? { it.first == :fast_forward })
    end
  end

  def test_a_fetch_only_project_reports_its_pin_and_never_moves
    with_runtime do |runtime|
      register(runtime, 'fresh', status: UNBORN, remote: 'git@forge.test:o/fresh.git',
                                 spec: { revision: PIN, sync_policy: 'FetchOnly' })
      register(runtime, 'tool', distance: distance(0, 2), fast_forward: TO_PIN,
                                spec: { revision: PIN, sync_policy: 'FetchOnly' })

      assert_equal [0, <<~TEXT, "2 projects: 2 unchanged\n"], run_sync(runtime:)
        project/fresh unchanged
          Revision: HEAD has no commits, manifest pins b2c3d4e; syncPolicy is FetchOnly
        project/tool unchanged
          Revision: HEAD is at a1b2c3d, manifest pins b2c3d4e; syncPolicy is FetchOnly
      TEXT
    end
  end

  private

  # The upstream holds the pin unless a test says otherwise.
  def distance(ahead, behind) = Slipway::Git::Distance.new(ahead:, behind:, off_upstream: 0)

  def run_sync(*, runtime:) = run_commands('sync', *, runtime:, commands: [Slipway::Commands::SyncCommand])
end
