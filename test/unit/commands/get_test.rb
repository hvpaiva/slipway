# frozen_string_literal: true

require 'test_helper'

class GetTest < Minitest::Test
  include CommandsHelper

  WIDE = <<~TABLE
    NAME    BRANCH   STATUS   FETCHED   AGE   PATH          HEAD      LAST-COMMIT   DRIFT
    fresh   main     Unborn   <never>   3h    ~/dev/fresh   <none>    <none>        Unborn
    hldr    main     Clean    12m       3h    ~/dev/hldr    a1b2c3d   45m           <none>
  TABLE
  ALL_GROUPS = <<~TABLE
    GROUP     NAME   BRANCH   STATUS   FETCHED   AGE
    default   hldr   main     Clean    <never>   3h
    work      job    main     Clean    <never>   3h
  TABLE
  BROKEN = <<~TABLE
    NAME     BRANCH   STATUS     FETCHED   AGE
    gone     <none>   Missing    <none>    3h
    plain    <none>   NotARepo   <none>    3h
    theirs   <none>   Unsafe     <none>    3h
  TABLE
  PAINTED = "\e[37mhldr\e[0m    \e[36mmain\e[0m     \e[32mClean\e[0m     \e[36m12m\e[0m       \e[37m3h\e[0m\n" \
            "\e[37mnotes\e[0m   \e[36mmain\e[0m     \e[33mDirty\e[0m     \e[90;3m<never>\e[0m   \e[37m3h\e[0m\n" \
            "\e[37mslow\e[0m    \e[90;3m<none>\e[0m   \e[90;3mUnknown\e[0m   \e[90;3m<none>\e[0m    \e[37m3h\e[0m\n"

  def test_all_groups_leaves_the_other_columns_with_the_colors_they_have_without_it
    with_runtime do |runtime|
      register(runtime, 'hldr')
      _, plain, = run_commands('get', 'projects', '--no-headers', '--color=always', runtime:)
      _, grouped, = run_commands('get', 'projects', '-A', '--no-headers', '--color=always', runtime:)

      assert_equal "\e[37mhldr\e[0m   \e[36mmain\e[0m   \e[32mClean\e[0m   \e[90;3m<never>\e[0m   \e[37m3h\e[0m\n",
                   plain
      assert_equal "\e[36mdefault\e[0m   \e[37mhldr\e[0m   \e[36mmain\e[0m   \e[32mClean\e[0m   " \
                   "\e[90;3m<never>\e[0m   \e[37m3h\e[0m\n", grouped
    end
  end

  def test_projects_print_as_a_table_of_the_current_group
    with_runtime do |runtime|
      register(runtime, 'hldr', labels: { 'lang' => 'rust' }, fetched_at: FETCHED)
      register(runtime, 'notes', status: DIRTY)
      register_group(runtime, 'work')
      register(runtime, 'job', group: 'work')
      expected = "NAME    BRANCH   STATUS   FETCHED   AGE\nhldr    main     Clean    12m       3h\n" \
                 "notes   main     Dirty    <never>   3h\n"

      assert_equal [0, expected, ''], run_commands('get', 'projects', runtime:)
      assert_equal expected, run_commands('get', 'proj', runtime:)[1]
    end
  end

  def test_wide_adds_path_head_last_commit_age_and_drift
    with_runtime do |runtime|
      register(runtime, 'hldr', fetched_at: FETCHED)
      register(runtime, 'fresh', status: UNBORN)

      assert_equal [0, WIDE, ''], run_commands('get', 'projects', '-o', 'wide', runtime:)
    end
  end

  def test_all_groups_prepends_the_group_column_and_spans_every_group
    with_runtime do |runtime|
      register_group(runtime, 'work')
      register(runtime, 'hldr')
      register(runtime, 'job', group: 'work')

      assert_equal [0, ALL_GROUPS, ''], run_commands('get', 'projects', '-A', runtime:)
      assert_equal ALL_GROUPS, run_commands('get', 'projects', '--all-groups', '-n', 'work', runtime:)[1]
    end
  end

  def test_the_group_flag_selects_another_group
    with_runtime do |runtime|
      register_group(runtime, 'work')
      register(runtime, 'hldr')
      register(runtime, 'job', group: 'work', status: DETACHED)

      assert_equal "NAME   BRANCH       STATUS     FETCHED   AGE\njob    (detached)   Detached   <never>   3h\n",
                   run_commands('get', 'projects', '-n', 'work', runtime:)[1]
    end
  end

  def test_show_labels_appends_the_labels_column
    with_runtime do |runtime|
      register(runtime, 'hldr', labels: { 'lang' => 'rust', 'app' => 'web' })
      register(runtime, 'notes')
      expected = "NAME    BRANCH   STATUS   FETCHED   AGE   LABELS\n" \
                 "hldr    main     Clean    <never>   3h    app=web,lang=rust\n" \
                 "notes   main     Clean    <never>   3h    <none>\n"

      assert_equal [0, expected, ''], run_commands('get', 'projects', '--show-labels', runtime:)
    end
  end

  def test_no_headers_drops_the_header_line
    with_runtime do |runtime|
      register(runtime, 'hldr')

      assert_equal [0, "hldr   main   Clean   <never>   3h\n", ''],
                   run_commands('get', 'projects', '--no-headers', runtime:)
    end
  end

  def test_the_selector_filters_by_labels
    with_runtime do |runtime|
      register(runtime, 'hldr', labels: { 'lang' => 'rust' })
      register(runtime, 'notes', labels: { 'lang' => 'md' })
      register(runtime, 'plain')

      assert_equal "NAME   BRANCH   STATUS   FETCHED   AGE\nhldr   main     Clean    <never>   3h\n",
                   run_commands('get', 'projects', '-l', 'lang=rust', runtime:)[1]
      assert_equal "NAME    BRANCH   STATUS   FETCHED   AGE\nnotes   main     Clean    <never>   3h\n" \
                   "plain   main     Clean    <never>   3h\n",
                   run_commands('get', 'projects', '--selector', 'lang!=rust', runtime:)[1]
      assert_equal "NAME    BRANCH   STATUS   FETCHED   AGE\nplain   main     Clean    <never>   3h\n",
                   run_commands('get', 'projects', '-l', '!lang', runtime:)[1]
    end
  end

  def test_names_select_specific_projects_in_the_given_order
    with_runtime do |runtime|
      register(runtime, 'hldr')
      register(runtime, 'notes')
      register(runtime, 'plain')

      assert_equal "NAME    BRANCH   STATUS   FETCHED   AGE\nplain   main     Clean    <never>   3h\n" \
                   "hldr    main     Clean    <never>   3h\n",
                   run_commands('get', 'projects', 'plain', 'hldr', runtime:)[1]
    end
  end

  def test_missing_and_broken_paths_show_their_state_with_no_branch
    with_runtime do |runtime|
      register(runtime, 'gone', status: nil)
      register_failing(runtime, 'plain', Slipway::Git::NotARepository)
      register_failing(runtime, 'theirs', Slipway::Git::UnsafeRepository)

      assert_equal [0, BROKEN, ''], run_commands('get', 'projects', runtime:)
    end
  end

  def test_unknown_states_warn_once_per_cause_before_the_table
    with_runtime do |runtime|
      register_failing(runtime, 'one', Slipway::Git::NotInstalled)
      register_failing(runtime, 'two', Slipway::Git::NotInstalled)
      register_failing(runtime, 'slow', Slipway::Git::Timeout)
      expected = "NAME   BRANCH   STATUS    FETCHED   AGE\none    <none>   Unknown   <none>    3h\n" \
                 "slow   <none>   Unknown   <none>    3h\ntwo    <none>   Unknown   <none>    3h\n"

      status, out, err = run_commands('get', 'projects', runtime:)

      assert_equal [0, expected], [status, out]
      assert_equal "warning: git executable \"git\" not found on PATH\nwarning: git did not finish within 10 seconds\n",
                   err
    end
  end

  def test_a_warning_makes_the_text_git_printed_visible
    with_runtime do |runtime, home|
      path = File.join(home, 'dev', 'odd')
      register_failing(runtime, 'odd', Slipway::Git::Error.new(path, "git exited with status 128: \e[2Jfatal\u202E"))

      _, _, err = run_commands('get', 'projects', runtime:)

      assert_equal "warning: git exited with status 128: ^[[2Jfatal\uFFFD\n", err
    end
  end

  def test_color_paints_status_by_state_and_the_warning_prefix
    with_runtime do |runtime|
      register(runtime, 'hldr', fetched_at: FETCHED)
      register(runtime, 'notes', status: DIRTY)
      register_failing(runtime, 'slow', Slipway::Git::Timeout)

      _, out, err = run_commands('get', 'projects', '--no-headers', '--color', runtime:)

      assert_equal PAINTED, out
      assert_equal "\e[33mwarning:\e[0m git did not finish within 10 seconds\n", err
    end
  end

  def test_usage_and_help_follow_the_registry
    with_runtime do |runtime|
      status, out, err = run_commands('get', '--help', runtime:)
      missing = run_commands('get', runtime:)

      assert_equal [0, ''], [status, err]
      assert_includes out, "Display one or many resources.\n\nPrints a table"
      assert_includes out, "Usage:\n  slipway get (TYPE [NAME...] | TYPE/NAME...) [flags]\n"
      assert_includes out, '  -A, --all-groups'
      assert_equal [2, '', "error: missing required argument \"TYPE\"\nSee 'slipway get --help' for usage.\n"], missing
    end
  end

  def test_help_explains_every_column_a_table_can_show
    headers = Slipway::Views::Project.headers(wide: true, group: true, labels: true) |
              Slipway::Views::Group.headers(wide: true, labels: true)

    assert_equal headers.sort, Slipway::Commands::Get::COLUMNS.keys.sort
  end
end
