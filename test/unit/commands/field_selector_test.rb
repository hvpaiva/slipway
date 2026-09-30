# frozen_string_literal: true

require 'json'
require 'test_helper'

class FieldSelectorFlagTest < Minitest::Test
  include CommandsHelper

  NOT_CLEAN = <<~TABLE
    NAME    BRANCH       STATUS     FETCHED   AGE
    gone    <none>       Missing    <none>    3h
    job     (detached)   Detached   <never>   3h
    notes   main         Dirty      <never>   3h
  TABLE
  UNSUPPORTED_BY_PROJECTS = <<~TEXT
    error: invalid field selector "status.phase=Running": field label not supported: "status.phase"
    See 'slipway get --help' for usage.
  TEXT
  UNSUPPORTED_BY_GROUPS = <<~TEXT
    error: invalid field selector "status.state=Clean": field label not supported: "status.state"
    See 'slipway describe --help' for usage.
  TEXT

  def test_get_filters_projects_on_the_state_git_answered
    with_runtime do |runtime|
      register_projects(runtime)

      assert_equal [0, NOT_CLEAN, ''],
                   run_commands('get', 'projects', '--field-selector', 'status.state!=Clean', runtime:)
      assert_equal "NAME   BRANCH   STATUS   FETCHED   AGE\nhldr   main     Clean    <never>   3h\n",
                   run_commands('get', 'projects', '--field-selector=status.state==Clean', runtime:)[1]
    end
  end

  def test_get_filters_on_metadata_and_spec_fields
    with_runtime do |runtime|
      register_projects(runtime)
      register_group(runtime, 'work')
      register(runtime, 'api', group: 'work')

      assert_equal "project/notes\n", run_commands('get', 'projects', '-o', 'name', '--field-selector',
                                                   'spec.path=~/dev/notes', runtime:)[1]
      assert_equal "project/api\n", run_commands('get', 'projects', '-A', '-o', 'name', '--field-selector',
                                                 'metadata.group=work', runtime:)[1]
      assert_equal "project/hldr\nproject/job\n", run_commands('get', 'projects', '-o', 'name', '--field-selector',
                                                               'metadata.name!=gone,metadata.name!=notes', runtime:)[1]
    end
  end

  def test_a_branch_the_object_leaves_out_compares_as_empty
    with_runtime do |runtime|
      register_projects(runtime)

      assert_equal "project/gone\nproject/job\n",
                   run_commands('get', 'projects', '-o', 'name', '--field-selector', 'status.branch=', runtime:)[1]
    end
  end

  def test_name_output_examines_the_projects_when_a_field_selector_needs_them
    with_runtime do |runtime|
      register(runtime, 'hldr')
      register_failing(runtime, 'slow', Slipway::Git::Timeout)

      assert_equal [0, "project/slow\n", "warning: git did not finish within 10 seconds\n"],
                   run_commands('get', 'projects', '-o', 'name', '--field-selector', 'status.state=Unknown', runtime:)
    end
  end

  def test_last_fetch_compares_as_never_without_a_fetch_on_record
    with_runtime do |runtime|
      register(runtime, 'hldr', fetched_at: Time.utc(2026, 9, 28, 12))
      register(runtime, 'notes')
      register(runtime, 'gone', status: nil)
      names = ->(fields) { run_commands('get', 'projects', '-o', 'name', '--field-selector', fields, runtime:)[1] }

      assert_equal "project/gone\nproject/notes\n", names.call('status.lastFetch=never')
      assert_equal "project/hldr\n", names.call('status.lastFetch!=never')
      assert_equal "project/hldr\n", names.call('status.lastFetch=2026-09-28T12:00:00Z')
      assert_empty names.call('status.lastFetch=2026-09-28')
    end
  end

  def test_structured_output_lists_what_matched
    with_runtime do |runtime|
      register_projects(runtime)

      _, out, = run_commands('get', 'projects', '-o', 'json', '--field-selector', 'status.state=Dirty', runtime:)

      assert_equal(['notes'], JSON.parse(out).fetch('items').map { it.dig('metadata', 'name') })
    end
  end

  def test_the_label_and_field_selectors_both_have_to_hold
    with_runtime do |runtime|
      register(runtime, 'hldr', labels: { 'lang' => 'rust' })
      register(runtime, 'notes', labels: { 'lang' => 'rust' }, status: DIRTY)
      register(runtime, 'site', status: DIRTY)

      assert_equal "project/notes\n", run_commands('get', 'projects', '-o', 'name', '-l', 'lang=rust',
                                                   '--field-selector', 'status.state=Dirty', runtime:)[1]
    end
  end

  def test_groups_match_on_their_name
    with_runtime do |runtime|
      register_group(runtime, 'work')
      register(runtime, 'hldr')

      assert_equal "NAME   PROJECTS   AGE\nwork   0          3h\n",
                   run_commands('get', 'groups', '--field-selector', 'metadata.name!=default', runtime:)[1]
      assert_equal "group/default\n",
                   run_commands('get', 'groups', '-o', 'name', '--field-selector', 'metadata.name=default', runtime:)[1]
      assert_equal %w[work], described(run_commands('describe', 'groups', '--field-selector', 'metadata.name=work',
                                                    runtime:))
    end
  end

  def test_describe_filters_projects_the_same_way
    with_runtime do |runtime|
      register_projects(runtime)

      assert_equal %w[gone job notes],
                   described(run_commands('describe', 'projects', '--field-selector', 'status.state!=Clean', runtime:))
      assert_equal %w[hldr],
                   described(run_commands('describe', 'projects', '--field-selector', 'status.branch=main,' \
                                                                                      'status.state=Clean', runtime:))
    end
  end

  def test_nothing_matched_says_so_on_stderr
    with_runtime do |runtime|
      register_projects(runtime)
      expected = [0, '', "No resources found in default group.\n"]

      assert_equal expected, run_commands('get', 'projects', '--field-selector', 'status.state=Behind', runtime:)
      assert_equal expected, run_commands('describe', 'projects', '--field-selector', 'status.state=Behind', runtime:)
      assert_equal [0, '', "No resources found.\n"],
                   run_commands('get', 'groups', '--field-selector', 'metadata.name=work', runtime:)
    end
  end

  def test_an_unsupported_field_is_a_usage_error_for_its_kind
    with_runtime do |runtime|
      register(runtime, 'hldr')

      assert_equal [2, '', UNSUPPORTED_BY_PROJECTS],
                   run_commands('get', 'projects', '--field-selector', 'status.phase=Running', runtime:)
      assert_equal [2, '', UNSUPPORTED_BY_GROUPS],
                   run_commands('describe', 'groups', '--field-selector', 'status.state=Clean', runtime:)
    end
  end

  def test_names_cannot_be_combined_with_a_field_selector
    with_runtime do |runtime|
      register(runtime, 'hldr')

      assert_equal [2, '', "error: name cannot be provided when a selector is specified\n" \
                           "See 'slipway get --help' for usage.\n"],
                   run_commands('get', 'project', 'hldr', '--field-selector', 'status.state=Clean', runtime:)
      assert_equal [2, '', "error: name cannot be provided when a selector is specified\n" \
                           "See 'slipway describe --help' for usage.\n"],
                   run_commands('describe', 'project', 'hldr', '--field-selector', 'bogus=zz', runtime:)
      assert_equal [0, "project/hldr\n", ''],
                   run_commands('get', 'project', 'hldr', '-o', 'name', '--field-selector', ' ', runtime:)
    end
  end

  private

  def register_projects(runtime)
    register(runtime, 'hldr')
    register(runtime, 'notes', status: DIRTY)
    register(runtime, 'gone', status: nil)
    register(runtime, 'job', status: DETACHED)
  end

  def described(result)
    status, out, err = result

    assert_equal [0, ''], [status, err]
    out.scan(/^Name: +(\S+)$/).flatten
  end
end
