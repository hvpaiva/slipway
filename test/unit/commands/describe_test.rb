# frozen_string_literal: true

require 'test_helper'

class DescribeTest < Minitest::Test
  include CommandsHelper

  FULL = <<~TEXT
    Name:         hldr
    Group:        default
    Labels:       lang=rust
    Created:      2026-09-29T09:00:00Z
    Age:          3h
    Path:         ~/dev/hldr
    Description:  Site and CLI
    Status:       Dirty
    Repository:
      Branch:      main
      Head:        a1b2c3d
      Upstream:    origin/main
      Ahead:       0
      Behind:      0
      Staged:      1
      Unstaged:    2
      Untracked:   3
      Conflicted:  0
      Stashes:     1
      Remote:      git@github.com:hvpaiva/hldr.git
      Last Fetch:  2026-09-29T11:48:00Z
    Last Commit:
      Hash:     a1b2c3d4e5f60718293a4b5c6d7e8f9012345678
      Author:   Ada Lovelace <ada@example.com>
      Date:     2026-09-29T11:15:00Z
      Subject:  initial commit
  TEXT

  def test_a_project_with_a_full_status_lists_every_section
    with_runtime do |runtime|
      register(runtime, 'hldr', labels: { 'lang' => 'rust' }, description: 'Site and CLI', status: DIRTY,
                                remote: 'git@github.com:hvpaiva/hldr.git', fetched_at: FETCHED)

      assert_equal [0, FULL, ''], run_commands('describe', 'project', 'hldr', runtime:)
    end
  end

  def test_a_missing_project_shows_the_reason_in_place_of_the_repository
    with_runtime do |runtime|
      register(runtime, 'gone', status: nil)
      expected = <<~TEXT
        Name:         gone
        Group:        default
        Labels:       <none>
        Created:      2026-09-29T09:00:00Z
        Age:          3h
        Path:         ~/dev/gone
        Description:  <none>
        Status:       Missing
        Repository:   no such directory
        Last Commit:  <none>
      TEXT

      assert_equal [0, expected, ''], run_commands('describe', 'projects', 'gone', runtime:)
    end
  end

  def test_several_objects_are_separated_by_one_blank_line
    with_runtime do |runtime|
      register(runtime, 'hldr')
      register(runtime, 'notes')

      status, out, err = run_commands('describe', 'projects', runtime:)

      assert_equal [0, ''], [status, err]
      assert_equal 2, out.scan(/^Name: /).size
      assert_includes out, "  Subject:  initial commit\n\nName:         notes\n"
      refute_match(/\n\n\z/, out)
    end
  end

  def test_the_selector_and_all_groups_narrow_and_widen_the_selection
    with_runtime do |runtime|
      register_group(runtime, 'work')
      register(runtime, 'hldr', labels: { 'lang' => 'rust' })
      register(runtime, 'job', group: 'work', labels: { 'lang' => 'rust' })
      register(runtime, 'notes', labels: { 'lang' => 'md' })

      _, selected, = run_commands('describe', 'projects', '-l', 'lang=rust', runtime:)
      _, everywhere, = run_commands('describe', 'projects', '-A', '-l', 'lang=rust', runtime:)

      assert_equal %w[hldr], selected.scan(/^Name: +(\S+)/).flatten
      assert_equal %w[hldr job], everywhere.scan(/^Name: +(\S+)/).flatten
    end
  end

  def test_a_group_lists_its_fields_and_project_count
    with_runtime do |runtime|
      register_group(runtime, 'work', labels: { 'team' => 'core' }, description: 'Day job')
      register(runtime, 'job', group: 'work')
      expected = <<~TEXT
        Name:         work
        Labels:       team=core
        Created:      2026-09-29T09:00:00Z
        Age:          3h
        Description:  Day job
        Projects:     1
      TEXT

      assert_equal [0, expected, ''], run_commands('describe', 'group', 'work', runtime:)
    end
  end

  def test_color_paints_keys_status_and_numbers
    with_runtime do |runtime|
      register(runtime, 'hldr')

      _, out, = run_commands('describe', 'project', 'hldr', '--color', runtime:)

      assert_includes out, "\e[96mStatus\e[0m:       \e[32mClean\e[0m\n"
      assert_includes out, "  \e[36mAhead\e[0m:       \e[35m0\e[0m\n"
    end
  end

  def test_unknown_states_warn_before_the_description
    with_runtime do |runtime|
      register_failing(runtime, 'slow', Slipway::Git::Timeout)

      status, out, err = run_commands('describe', 'projects', runtime:)

      assert_equal 0, status
      assert_equal "warning: git did not finish within 10 seconds\n", err
      assert_includes out, "Status:       Unknown\nRepository:   git did not finish within 10 seconds\n" \
                           "Last Commit:  <none>\n"
    end
  end

  def test_nothing_selected_says_so_on_stderr
    with_runtime do |runtime|
      assert_equal [0, '', "No resources found in default group.\n"], run_commands('describe', 'projects', runtime:)
      assert_equal [0, '', "No resources found.\n"], run_commands('describe', 'projects', '-A', runtime:)
      assert_equal [0, '', "No resources found.\n"], run_commands('describe', 'groups', runtime:)
    end
  end

  def test_errors_match_get
    with_runtime do |runtime|
      register(runtime, 'hldr')

      assert_equal [1, '', "error: projects \"nope\" not found\n"],
                   run_commands('describe', 'projects', 'nope', runtime:)
      assert_equal [1, '', "error: unknown resource type \"pod\" (known types: projects, groups)\n"],
                   run_commands('describe', 'pod', 'x', runtime:)
      assert_equal [2, '', "error: a resource cannot be retrieved by name across all groups\n" \
                           "See 'slipway describe --help' for usage.\n"],
                   run_commands('describe', 'projects', 'hldr', '-A', runtime:)
    end
  end

  def test_help_follows_the_registry
    with_runtime do |runtime|
      status, out, err = run_commands('describe', '-h', runtime:)

      assert_equal [0, ''], [status, err]
      assert_includes out, "Show details of one or many resources.\n\nPrint a detailed"
      assert_includes out, "Usage:\n  slipway describe (TYPE [NAME...] | TYPE/NAME...) [flags]\n"
      refute_includes out, '--output'
    end
  end
end
