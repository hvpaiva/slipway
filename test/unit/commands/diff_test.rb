# frozen_string_literal: true

require 'test_helper'

class DiffTest < Minitest::Test
  include CommandsHelper

  COMMANDS = [Slipway::Commands::Diff].freeze
  BEHIND = CLEAN.with(behind: 3)
  URL = 'git@github.com:hvpaiva/hldr.git'

  def test_a_project_that_matches_its_manifest_prints_nothing_and_exits_zero
    with_runtime do |runtime|
      register(runtime, 'hldr', remote: URL, spec: { remote: URL, branch: 'main' })
      register(runtime, 'notes', status: CLEAN.with(ahead: 2, untracked: 1))

      assert_equal [0, '', ''], diff(runtime)
    end
  end

  def test_each_project_that_differs_prints_its_name_then_one_line_per_item_in_input_order
    with_runtime do |runtime|
      register(runtime, 'augur', status: BEHIND.with(ahead: 1), remote: 'git@forge.test:o/augur.git',
                                 spec: { remote: URL })
      register(runtime, 'clean')
      register(runtime, 'hldr', status: BEHIND)

      assert_equal [3, <<~TEXT, ''], diff(runtime)
        project/augur
          Remote: origin is git@forge.test:o/augur.git, manifest says #{URL}; sync never changes a remote
            git -C ~/dev/augur remote set-url origin #{URL}
          Behind: 3 commits behind origin/main
          Diverged: 1 ahead, 3 behind origin/main; sync never merges or rebases
            git -C ~/dev/augur log --oneline --left-right HEAD...@{upstream}
        project/hldr
          Behind: 3 commits behind origin/main; sync will fast-forward
      TEXT
    end
  end

  def test_color_paints_drift_yellow_blockers_red_and_commands_muted
    with_runtime do |runtime|
      register(runtime, 'hldr', status: BEHIND.with(staged: 1))

      _, out, = diff(runtime, '--color=always')

      assert_equal "project/hldr\n  \e[33mBehind:\e[0m 3 commits behind origin/main\n  \e[31mDirty:\e[0m 1 staged; " \
                   "sync fast-forwards only a tree without staged or unstaged changes\n    " \
                   "\e[90;3mgit -C ~/dev/hldr status\e[0m\n", out
    end
  end

  def test_text_from_git_is_made_plain
    with_runtime do |runtime|
      register(runtime, 'hldr', status: BEHIND.with(upstream: "origin/ma\e[2Jin"))

      assert_equal [3, "project/hldr\n  Behind: 3 commits behind origin/ma^[[2Jin; sync will fast-forward\n", ''],
                   diff(runtime)
    end
  end

  def test_a_command_line_is_made_plain
    with_runtime do |runtime|
      register(runtime, 'hldr', status: nil, spec: { path: "~/dev/hl\e[2Jdr", remote: URL })

      assert_equal [3, "project/hldr\n  Missing: no directory at ~/dev/hl^[[2Jdr\n    " \
                       "git clone -- #{URL} ~/dev/hl\\^[\\[2Jdr\n", ''],
                   diff(runtime)
    end
  end

  def test_a_project_git_could_not_answer_for_is_listed_and_exits_one
    with_runtime do |runtime|
      register(runtime, 'hldr')
      register_failing(runtime, 'slow', Slipway::Git::Timeout)

      assert_equal [1, "project/slow\n  Unknown: git did not finish within 10 seconds\n",
                    "warning: git did not finish within 10 seconds\n"], diff(runtime)
    end
  end

  def test_names_select_projects_and_one_not_found_exits_one_after_the_others_print
    with_runtime do |runtime|
      register(runtime, 'hldr', status: BEHIND)
      register(runtime, 'notes', status: BEHIND)

      assert_equal [3, "project/notes\n  Behind: 3 commits behind origin/main; sync will fast-forward\n", ''],
                   diff(runtime, 'project/notes')
      assert_equal [1, "project/hldr\n  Behind: 3 commits behind origin/main; sync will fast-forward\n",
                    "error: projects \"gone\" not found\n"], diff(runtime, 'hldr', 'gone')
    end
  end

  def test_the_selector_and_all_groups_pick_the_projects
    with_runtime do |runtime|
      register_group(runtime, 'work')
      register(runtime, 'hldr', status: BEHIND, labels: { 'lang' => 'rust' })
      register(runtime, 'api', group: 'work', status: BEHIND, labels: { 'lang' => 'rust' })
      register(runtime, 'notes', status: BEHIND)

      _, selected, = diff(runtime, '-l', 'lang=rust')
      _, everywhere, = diff(runtime, '-A', '-l', 'lang=rust')

      assert_equal %w[project/hldr], selected.scan(%r{^project/\S+})
      assert_equal %w[project/hldr project/api], everywhere.scan(%r{^project/\S+})
    end
  end

  def test_no_project_selected_says_so_and_exits_zero
    with_runtime do |runtime|
      assert_equal [0, '', "No resources found in default group.\n"], diff(runtime)
    end
  end

  def test_groups_and_names_across_groups_are_usage_errors
    with_runtime do |runtime|
      status, _, err = diff(runtime, 'group/work')

      assert_equal [2, "error: cannot diff a group\nSee 'slipway diff --help' for usage.\n"], [status, err]
      assert_equal 2, diff(runtime, 'hldr', '-A').first
    end
  end

  private

  def diff(runtime, *) = run_commands('diff', *, runtime:, commands: COMMANDS)
end
