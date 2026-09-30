# frozen_string_literal: true

require 'test_helper'

class SyncTest < Minitest::Test
  include CommandsHelper

  NEW = 'e4f5a6b7c8d9e0f1a2b3c4d5e6f7a8b9c0d1e2f3'
  MOVED = Slipway::Git::FetchResult.new(updates: [['refs/remotes/origin/main', SHA, NEW]])
  BEHIND = CLEAN.with(behind: 3)
  MOVE = Slipway::Git::FastForward.new(from: SHA, to: NEW, count: 3)
  NOTES = 'git@github.com:hvpaiva/notes.git'
  EVERY_OUTCOME = <<~TEXT.freeze
    project/api denied (AuthRequired)
      Permission denied (publickey).
      Run 'git -C <home>/dev/api fetch' once in a terminal to see what git needs.
    project/cli skipped (Busy)
      another git process holds index.lock, or one left it behind; sync never removes a lock
    project/dots paused
    project/hldr fast-forwarded
      main a1b2c3d..e4f5a6b (3 commits); undo with 'slipway rollout undo project/hldr'
    project/notes unchanged
      Remote: origin is https://github.com/hvpaiva/notes.git, manifest says #{NOTES}; sync never changes a remote
    project/old skipped (Missing)
      no directory at ~/dev/old
    project/slipway skipped (Dirty)
      2 staged, 1 unstaged; sync fast-forwards only a tree without staged or unstaged changes
      git -C ~/dev/slipway status
    project/tool fetched
      origin/main a1b2c3d..e4f5a6b
      Behind: 3 commits behind origin/main; syncPolicy is FetchOnly
    project/web skipped (WouldOverwrite)
      the incoming commits would overwrite untracked files; move them and run sync again
      git -C ~/dev/web status
  TEXT
  DRY_RUN = <<~TEXT
    project/hldr fast-forwarded (dry run)
      Behind: 3 commits behind origin/main; sync will fast-forward
    project/dirty skipped (Dirty) (dry run)
      1 staged; sync fast-forwards only a tree without staged or unstaged changes
      git -C ~/dev/dirty status
    project/same unchanged (dry run)
  TEXT

  def test_each_project_prints_its_result_and_details_in_the_order_listed
    with_runtime do |runtime, home|
      register_every_outcome(runtime, home)

      assert_equal [1, EVERY_OUTCOME.gsub('<home>', home),
                    "9 projects: 1 fast-forwarded, 1 fetched, 1 unchanged, 4 skipped, 1 paused, 1 denied\n"],
                   run_sync(runtime:)
    end
  end

  def test_a_branch_behind_its_upstream_moves_and_the_second_run_finds_it_unchanged
    with_runtime do |runtime|
      register(runtime, 'hldr', status: BEHIND, fast_forward: MOVE)
      moved = "project/hldr fast-forwarded\n  main a1b2c3d..e4f5a6b (3 commits); undo with " \
              "'slipway rollout undo project/hldr'\n"

      assert_equal [0, moved, ''], run_sync(runtime:)
      assert_equal [0, "project/hldr unchanged\n", ''], run_sync(runtime:)
    end
  end

  def test_the_status_is_one_only_when_a_fetch_or_a_fast_forward_was_denied_or_failed
    with_runtime do |runtime, home|
      register(runtime, 'api', fetch: Slipway::Git::AuthRequired)
      register(runtime, 'big', status: BEHIND, fast_forward: Slipway::Git::Timeout.new("#{home}/dev/big", seconds: 60))
      register(runtime, 'dirty', status: BEHIND.with(unstaged: 1))
      register(runtime, 'same')

      assert_equal 0, run_sync('dirty', 'same', runtime:).first
      assert_equal 1, run_sync('api', runtime:).first
      assert_equal [1, "project/big failed (Timeout)\n  git did not finish within 60 seconds\n", ''],
                   run_sync('big', runtime:)
    end
  end

  def test_color_paints_each_word_with_its_role_and_mutes_details_and_the_summary
    with_runtime do |runtime|
      register(runtime, 'hldr', status: BEHIND, fast_forward: MOVE)
      register(runtime, 'same')
      register(runtime, 'tool', status: BEHIND, fetch: MOVED, spec: { sync_policy: 'FetchOnly' })

      status, out, err = run_sync('--color=always', runtime:)
      words = out.lines.grep(/\Aproject/).map { it[/ (\e.*)$/, 1] }

      assert_equal [0, ["\e[32mfast-forwarded\e[0m", "\e[35munchanged\e[0m", "\e[32mfetched\e[0m"]], [status, words]
      assert_includes out, "  \e[90;3mmain a1b2c3d..e4f5a6b (3 commits); undo with 'slipway rollout undo " \
                           "project/hldr'\e[0m\n"
      assert_equal "\e[90;3m3 projects: 1 fast-forwarded, 1 fetched, 1 unchanged\e[0m\n", err
    end
  end

  def test_a_dry_run_prints_the_plan_from_the_last_fetch_and_warns_about_projects_never_fetched
    with_runtime do |runtime|
      register(runtime, 'hldr', status: BEHIND, fetched_at: FETCHED, fast_forward: MOVE)
      register(runtime, 'dirty', status: BEHIND.with(staged: 1))
      register(runtime, 'same', fetched_at: FETCHED)
      warning = "warning: 1 project was never fetched and a dry run does not fetch; run 'slipway fetch' first " \
                "for an up-to-date plan\n"

      assert_equal [0, DRY_RUN, "#{warning}3 projects: 1 fast-forwarded, 1 unchanged, 1 skipped (dry run)\n"],
                   run_sync('hldr', 'dirty', 'same', '--dry-run', runtime:)
    end
  end

  # A paused project and one git cannot read would not be fetched either, so they do not count.
  def test_the_warning_counts_only_the_projects_a_fetch_would_reach
    with_runtime do |runtime|
      %w[a b].each { register(runtime, it) }
      register(runtime, 'dots', paused: true)
      register(runtime, 'old', status: nil)

      assert_match(/\Awarning: 2 projects were never fetched and a dry run does not fetch;/,
                   run_sync('--dry-run', runtime:).last)
    end
  end

  # dots would be denied if it were read, so its word shows that it was not.
  def test_a_paused_project_runs_no_git_in_a_run_or_a_dry_run
    with_runtime do |runtime|
      register(runtime, 'dots', paused: true, fetch: Slipway::Git::AuthRequired)
      register(runtime, 'hldr', status: BEHIND, fast_forward: MOVE)

      assert_equal 0, run_sync(runtime:).first
      assert_equal 0, run_sync('--dry-run', runtime:).first
      assert_equal(%w[hldr], runtime.git.calls.map { File.basename(it[1]) }.uniq)
    end
  end

  # Only a FetchOnly project reports what its fetch brought; any other reports its branch.
  def test_a_branch_that_stays_is_unchanged_whatever_its_fetch_brought
    with_runtime do |runtime|
      register(runtime, 'same', fetch: MOVED)
      register(runtime, 'tool', fetch: MOVED, spec: { sync_policy: 'FetchOnly' })

      assert_equal [0, "project/same unchanged\nproject/tool fetched\n  origin/main a1b2c3d..e4f5a6b\n",
                    "2 projects: 1 fetched, 1 unchanged\n"], run_sync(runtime:)
    end
  end

  def test_names_select_projects_and_a_group_is_never_a_target
    with_runtime do |runtime|
      register(runtime, 'hldr')

      assert_equal [0, "project/hldr unchanged\n", ''], run_sync('project/hldr', runtime:)
      assert_equal [2, '', "error: cannot sync a group\nSee 'slipway sync --help' for usage.\n"],
                   run_sync('group/default', runtime:)
      assert_equal [2, '', "error: cannot sync a project by name across all groups\n" \
                           "See 'slipway sync --help' for usage.\n"], run_sync('hldr', '-A', runtime:)
      assert_equal [0, '', "No resources found in work group.\n"], run_sync('-n', 'work', runtime:)
    end
  end

  private

  def run_sync(*, runtime:) = run_commands('sync', *, runtime:, commands: [Slipway::Commands::Sync])

  def register_every_outcome(runtime, home)
    register(runtime, 'api', fetch: Slipway::Git::AuthRequired.new("#{home}/dev/api", 'Permission denied (publickey).'))
    register(runtime, 'cli', status: BEHIND, fast_forward: Slipway::Git::Busy)
    register(runtime, 'dots', paused: true, fetch: Slipway::Git::AuthRequired)
    register(runtime, 'hldr', status: BEHIND, fetch: MOVED, fast_forward: MOVE)
    register(runtime, 'notes', remote: 'https://github.com/hvpaiva/notes.git', spec: { remote: NOTES })
    register(runtime, 'old', status: nil)
    register(runtime, 'slipway', status: BEHIND.with(staged: 2, unstaged: 1), fetch: MOVED)
    register(runtime, 'tool', status: BEHIND, fetch: MOVED, spec: { sync_policy: 'FetchOnly' })
    register(runtime, 'web', status: BEHIND, fast_forward: Slipway::Git::WouldOverwrite)
  end
end
