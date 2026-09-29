# frozen_string_literal: true

require 'test_helper'

# `delete`: projects and groups by name, resolution before removal, --ignore-not-found and the dry run.
class DeleteTest < Minitest::Test
  include CommandsHelper

  PROJECTS = Slipway::Resources.resolve('projects')
  GROUPS = Slipway::Resources.resolve('groups')
  HINT = "See 'slipway delete --help' for usage.\n"

  def test_deletes_projects_from_the_current_group_in_the_order_given
    with_runtime do |runtime|
      register(runtime, 'hldr')
      register(runtime, 'notes')
      register(runtime, 'keep')

      assert_equal [0, "project \"notes\" deleted from default group\n" \
                       "project \"hldr\" deleted from default group\n", ''],
                   run_delete('projects', 'notes', 'hldr', runtime:)
      assert_equal %w[keep], runtime.store.names(PROJECTS)
    end
  end

  def test_the_group_flag_selects_the_group
    with_runtime do |runtime|
      register_group(runtime, 'work')
      register(runtime, 'api', group: 'work')
      register(runtime, 'api')

      result = run_delete('project', 'api', '-n', 'work', runtime:)
      remaining = runtime.store.list(PROJECTS).map { [it.name, it.group] }

      assert_equal [0, "project \"api\" deleted from work group\n", ''], result
      assert_equal [%w[api default]], remaining
    end
  end

  def test_deleting_a_group_removes_the_registrations_of_its_projects
    with_runtime do |runtime|
      register_group(runtime, 'work')
      register(runtime, 'api', group: 'work')
      register(runtime, 'hldr')

      assert_equal [0, "group \"work\" deleted\n", ''], run_delete('group', 'work', runtime:)
      assert_equal %w[default], runtime.store.names(GROUPS)
      assert_equal %w[hldr], runtime.store.names(PROJECTS)
    end
  end

  def test_a_missing_name_aborts_before_anything_is_deleted
    with_runtime do |runtime|
      register(runtime, 'hldr')
      register_group(runtime, 'work')

      assert_equal [1, '', "error: projects \"missing\" not found\n"],
                   run_delete('projects', 'hldr', 'missing', runtime:)
      assert_equal [1, '', "error: groups \"other\" not found\n"], run_delete('groups', 'work', 'other', runtime:)
      assert_equal %w[hldr], runtime.store.names(PROJECTS)
      assert_equal %w[default work], runtime.store.names(GROUPS)
    end
  end

  def test_ignore_not_found_skips_missing_names_silently
    with_runtime do |runtime|
      register(runtime, 'hldr')

      assert_equal [0, "project \"hldr\" deleted from default group\n", ''],
                   run_delete('projects', 'missing', 'hldr', '--ignore-not-found', runtime:)
      assert_equal [0, '', ''], run_delete('projects', 'missing', '--ignore-not-found', runtime:)
      assert_empty runtime.store.names(PROJECTS)
    end
  end

  def test_the_default_group_cannot_be_deleted_even_among_other_names
    with_runtime do |runtime|
      register_group(runtime, 'work')
      register(runtime, 'hldr')

      assert_equal [1, '', "error: the default group cannot be deleted\n"], run_delete('group', 'default', runtime:)
      assert_equal [1, '', "error: the default group cannot be deleted\n"],
                   run_delete('groups', 'work', 'default', runtime:)
      assert_equal [1, '', "error: the default group cannot be deleted\n"],
                   run_delete('groups', 'default', '--dry-run=client', runtime:)
      assert_equal %w[default work], runtime.store.names(GROUPS)
    end
  end

  def test_dry_run_prints_the_lines_and_writes_nothing
    with_runtime do |runtime|
      register_group(runtime, 'work')
      register(runtime, 'hldr')
      plain = run_delete('projects', 'hldr', '--dry-run', 'client', runtime:)
      painted = run_delete('group', 'work', '--dry-run=client', '--color', runtime:)

      assert_equal [0, "project \"hldr\" deleted from default group (dry run)\n", ''], plain
      assert_equal [0, "group \"work\" \e[31mdeleted\e[0m \e[36m(dry run)\e[0m\n", ''], painted
      assert_equal %w[hldr], runtime.store.names(PROJECTS)
      assert_equal %w[default work], runtime.store.names(GROUPS)
    end
  end

  def test_a_repeated_name_is_deleted_once
    with_runtime do |runtime|
      register(runtime, 'hldr')

      assert_equal [0, "project \"hldr\" deleted from default group\n", ''],
                   run_delete('projects', 'hldr', 'hldr', runtime:)
    end
  end

  def test_refusals_help_and_arity
    with_runtime do |runtime|
      status, out, err = run_delete('--help', runtime:)

      assert_equal [0, ''], [status, err]
      assert_includes out, "Delete resources by type and name.\n\n"
      assert_includes out, "Usage:\n  slipway delete (TYPE NAME... | TYPE/NAME...) [flags]\n"
      assert_includes out, '      --ignore-not-found'
      assert_equal [2, '', "error: resource(s) were provided, but no name was specified\n#{HINT}"],
                   run_delete('projects', runtime:)
      assert_equal [1, '', "error: unknown resource type \"pods\" (known types: projects, groups)\n"],
                   run_delete('pods', 'x', runtime:)
    end
  end

  private

  def run_delete(*argv, runtime:, **)
    run_commands('delete', *argv, runtime:, commands: [Slipway::Commands::Delete], **)
  end
end
