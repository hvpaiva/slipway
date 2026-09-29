# frozen_string_literal: true

require 'json'
require 'test_helper'

class GetFormatsTest < Minitest::Test
  include CommandsHelper

  CLEAN_STATUS = { 'branch' => 'main', 'head' => 'a1b2c3d', 'upstream' => 'origin/main', 'ahead' => 0, 'behind' => 0,
                   'staged' => 0, 'unstaged' => 0, 'untracked' => 0, 'conflicted' => 0, 'stashes' => 0,
                   'state' => 'Clean',
                   'lastCommit' => { 'hash' => SHA, 'author' => 'Ada Lovelace', 'email' => 'ada@example.com',
                                     'date' => '2026-09-29T11:15:00Z', 'subject' => 'initial commit' } }.freeze
  MISSING_YAML = <<~YAML
    kind: Project
    metadata:
      name: gone
      group: default
      labels: {}
      creationTimestamp: '2026-09-29T09:00:00Z'
    spec:
      path: "~/dev/gone"
    status:
      state: Missing
  YAML
  GROUP_YAML = <<~YAML
    kind: Group
    metadata:
      name: work
      labels:
        team: core
      creationTimestamp: '2026-09-29T09:00:00Z'
    spec: {}
    status:
      projects: 1
  YAML
  GROUPS = "NAME      PROJECTS   AGE\ndefault   2          3h\nwork      1          3h\n"
  GROUPS_WIDE = <<~TABLE
    NAME      PROJECTS   AGE   DESCRIPTION
    default   2          3h    <none>
    work      1          3h    Day job
  TABLE

  def test_name_output_prints_type_slash_name_without_inspecting
    with_runtime do |runtime|
      register(runtime, 'hldr')
      register_failing(runtime, 'slow', Slipway::Git::Timeout)
      register_group(runtime, 'work')

      assert_equal [0, "project/hldr\nproject/slow\n", ''], run_commands('get', 'projects', '-o', 'name', runtime:)
      assert_equal [0, "group/default\ngroup/work\n", ''], run_commands('get', 'groups', '-o', 'name', runtime:)
    end
  end

  def test_json_of_one_name_prints_the_object_alone
    with_runtime do |runtime|
      register(runtime, 'hldr', labels: { 'lang' => 'rust' }, description: 'Site', remote: 'git@x:h.git')

      status, out, err = run_commands('get', 'project', 'hldr', '-o', 'json', runtime:)
      single = JSON.parse(out)

      assert_equal [0, ''], [status, err]
      assert out.start_with?("{\n  \"kind\": \"Project\",\n  \"metadata\": {\n    \"name\": \"hldr\",\n")
      assert_equal %w[kind metadata spec status], single.keys
      assert_equal({ 'path' => '~/dev/hldr', 'description' => 'Site' }, single.fetch('spec'))
      assert_equal CLEAN_STATUS, single.fetch('status')
    end
  end

  def test_json_of_several_projects_prints_a_list
    with_runtime do |runtime|
      register(runtime, 'hldr')
      register(runtime, 'gone', status: nil)

      _, listed, = run_commands('get', 'projects', '-o', 'json', runtime:)
      _, named, = run_commands('get', 'projects', 'hldr', 'gone', '-o', 'json', runtime:)
      list = JSON.parse(listed)

      assert_equal 'List', list.fetch('kind')
      assert_equal([%w[gone Missing], %w[hldr Clean]],
                   list.fetch('items').map { [it.dig('metadata', 'name'), it.dig('status', 'state')] })
      assert_equal(%w[hldr gone], JSON.parse(named).fetch('items').map { it.dig('metadata', 'name') })
    end
  end

  def test_yaml_prints_the_manifest_followed_by_the_status
    with_runtime do |runtime|
      register(runtime, 'gone', status: nil)

      assert_equal [0, MISSING_YAML, ''], run_commands('get', 'projects', 'gone', '-o', 'yaml', runtime:)
      _, listed, = run_commands('get', 'projects', '-o', 'yaml', runtime:)

      assert listed.start_with?("kind: List\nitems:\n- kind: Project\n")
    end
  end

  def test_groups_list_with_project_counts_and_descriptions
    with_runtime do |runtime|
      register_group(runtime, 'work', description: 'Day job')
      register(runtime, 'hldr')
      register(runtime, 'notes')
      register(runtime, 'job', group: 'work')

      assert_equal [0, GROUPS, ''], run_commands('get', 'groups', runtime:)
      assert_equal GROUPS_WIDE, run_commands('get', 'groups', '-o', 'wide', '-A', runtime:)[1]
      assert_equal "work   1   3h\n", run_commands('get', 'group', 'work', '--no-headers', runtime:)[1]
    end
  end

  def test_a_single_group_serializes_with_its_project_count
    with_runtime do |runtime|
      register_group(runtime, 'work', labels: { 'team' => 'core' })
      register(runtime, 'job', group: 'work')

      _, json, = run_commands('get', 'group', 'work', '-o', 'json', runtime:)

      assert_equal [0, GROUP_YAML, ''], run_commands('get', 'groups', 'work', '-o', 'yaml', runtime:)
      assert_equal({ 'projects' => 1 }, JSON.parse(json).fetch('status'))
    end
  end

  def test_nothing_selected_says_so_on_stderr_and_succeeds
    with_runtime do |runtime|
      register_group(runtime, 'work')
      register(runtime, 'hldr', labels: { 'lang' => 'rust' })

      assert_equal [0, '', "No resources found in work group.\n"],
                   run_commands('get', 'projects', '-n', 'work', runtime:)
      assert_equal [0, '', "No resources found in default group.\n"],
                   run_commands('get', 'projects', '-l', 'lang=go', runtime:)
      assert_equal [0, '', "No resources found.\n"], run_commands('get', 'projects', '-A', '-l', 'lang=go', runtime:)
      assert_equal [0, '', "No resources found.\n"], run_commands('get', 'groups', '-l', 'team=core', runtime:)
    end
  end

  def test_an_empty_store_has_no_groups_either
    with_runtime do |runtime|
      assert_equal [0, '', "No resources found.\n"], run_commands('get', 'groups', runtime:)
      assert_equal [0, '', "No resources found in default group.\n"], run_commands('get', 'projects', runtime:)
    end
  end

  def test_a_missing_name_is_a_runtime_error_reported_after_the_names_that_exist
    with_runtime do |runtime|
      register(runtime, 'hldr')

      assert_equal [1, '', "error: projects \"hldr\" not found\n"],
                   run_commands('get', 'projects', 'hldr', '-n', 'work', runtime:)
      assert_equal [1, "NAME   BRANCH   STATUS   FETCHED   AGE\nhldr   main     Clean    <never>   3h\n",
                    "error: projects \"nope\" not found\n"], run_commands('get', 'projects', 'hldr', 'nope', runtime:)
      assert_equal [1, '', "error: groups \"work\" not found\n"], run_commands('get', 'groups', 'work', runtime:)
    end
  end

  def test_an_unknown_type_is_a_runtime_error
    with_runtime do |runtime|
      assert_equal [1, '', "error: unknown resource type \"pods\" (known types: projects, groups)\n"],
                   run_commands('get', 'pods', runtime:)
    end
  end

  def test_a_malformed_selector_is_a_usage_error
    with_runtime do |runtime|
      status, out, err = run_commands('get', 'projects', '-l', 'a=b,', runtime:)

      assert_equal [2, ''], [status, out]
      assert_equal "error: invalid selector \"a=b,\": expected a requirement after ','\n" \
                   "See 'slipway get --help' for usage.\n", err
    end
  end

  def test_names_cannot_be_combined_with_a_selector_or_all_groups
    with_runtime do |runtime|
      register(runtime, 'hldr')

      assert_equal [2, '', "error: name cannot be provided when a selector is specified\n" \
                           "See 'slipway get --help' for usage.\n"],
                   run_commands('get', 'projects', 'hldr', '-l', 'a=b', runtime:)
      assert_equal [2, '', "error: a resource cannot be retrieved by name across all groups\n" \
                           "See 'slipway get --help' for usage.\n"],
                   run_commands('get', 'projects', 'hldr', '-A', runtime:)
    end
  end
end
