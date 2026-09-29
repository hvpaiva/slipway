# frozen_string_literal: true

require 'test_helper'

class CreateTest < Minitest::Test
  include CommandsHelper

  PROJECTS = Slipway::Resources.resolve('projects')
  GROUPS = Slipway::Resources.resolve('groups')
  HINT = "See 'slipway create --help' for usage.\n"

  def test_creates_a_project_in_the_default_group_and_the_default_group_itself
    with_runtime do |runtime|
      result = run_create('project', 'hldr', '--path', '~/dev/hldr', runtime:)
      project = runtime.store.find(PROJECTS, 'hldr', group: nil)

      assert_equal [0, "project/hldr created\n", ''], result
      assert_equal Slipway::Project.new(name: 'hldr', created_at: CREATED, path: '~/dev/hldr'), project
      assert runtime.store.exist?(GROUPS, 'default', group: nil)
    end
  end

  def test_creates_a_project_with_labels_and_a_description_in_the_group_flag
    with_runtime do |runtime|
      register_group(runtime, 'work')
      result = run_create('projects', 'api', '--path', '~/work/api', '-n', 'work', '--label', 'lang=go',
                          '--label', 'tier=api', '--description', 'Public API', runtime:)
      project = runtime.store.find(PROJECTS, 'api', group: 'work')

      assert_equal [0, "project/api created\n", ''], result
      assert_equal ['work', { 'lang' => 'go', 'tier' => 'api' }, 'Public API'],
                   [project.group, project.labels, project.description]
    end
  end

  def test_creates_a_group_with_labels_and_a_description
    with_runtime do |runtime|
      result = run_create('group', 'work', '--description', 'Day job', '--label', 'owner=me', runtime:)
      group = runtime.store.find(GROUPS, 'work', group: nil)

      assert_equal [0, "group/work created\n", ''], result
      assert_equal ['work', { 'owner' => 'me' }, CREATED, 'Day job'], group.to_h.values
      assert_equal [0, "group/team created\n", ''], run_create('groups', 'team', runtime:)
    end
  end

  def test_path_is_required_for_projects_and_refused_for_groups
    with_runtime do |runtime|
      assert_equal [2, '', "error: required flag(s) \"--path\" not set\n#{HINT}"],
                   run_create('project', 'hldr', runtime:)
      assert_equal [2, '', "error: flag --path applies to projects only\n#{HINT}"],
                   run_create('group', 'work', '--path', '~/work', runtime:)
      assert_empty runtime.store.list(GROUPS)
    end
  end

  def test_an_existing_resource_is_a_conflict
    with_runtime do |runtime|
      register(runtime, 'hldr')
      register_group(runtime, 'work')

      assert_equal [1, '', "error: project \"hldr\" already exists\n"],
                   run_create('project', 'hldr', '--path', '~/elsewhere', runtime:)
      assert_equal [1, '', "error: group \"work\" already exists\n"], run_create('group', 'work', runtime:)
      assert_equal '~/dev/hldr', runtime.store.find(PROJECTS, 'hldr', group: nil).path
    end
  end

  def test_a_project_needs_its_group_to_exist
    with_runtime do |runtime|
      assert_equal [1, '', "error: groups \"work\" not found\n"],
                   run_create('project', 'hldr', '--path', '~/dev/hldr', '-n', 'work', runtime:)
      assert_empty runtime.store.list(PROJECTS)
    end
  end

  def test_invalid_names_and_labels_are_refused
    with_runtime do |runtime|
      rule = Slipway::Names::RULE

      assert_equal [2, '', "error: \"Bad_Name\" is not a valid project name: #{rule}\n#{HINT}"],
                   run_create('project', 'Bad_Name', '--path', '~/x', runtime:)
      assert_equal [2, '', "error: invalid label \"lang\": expected KEY=VALUE\n#{HINT}"],
                   run_create('project', 'hldr', '--path', '~/x', '--label', 'lang', runtime:)
      assert_equal [2, '', "error: label \"lang\" is given more than once\n#{HINT}"],
                   run_create('group', 'work', '--label', 'lang=go', '--label', 'lang=rust', runtime:)
      assert_equal [1, '', "error: unknown resource type \"pods\" (known types: projects, groups)\n"],
                   run_create('pods', 'x', runtime:)
    end
  end

  def test_dry_run_prints_the_result_and_writes_nothing
    with_runtime do |runtime|
      plain = run_create('project', 'hldr', '--path', '~/dev/hldr', '--dry-run', 'client', runtime:)
      painted = run_create('group', 'work', '--dry-run=client', '--color', runtime:)

      assert_equal [0, "project/hldr created (dry run)\n", ''], plain
      assert_equal [0, "group/work \e[32mcreated\e[0m \e[36m(dry run)\e[0m\n", ''], painted
      assert_empty runtime.store.list(PROJECTS)
      assert_empty runtime.store.list(GROUPS)
    end
  end

  def test_dry_run_still_checks_the_name_the_labels_and_the_group
    with_runtime do |runtime|
      register_group(runtime, 'work')
      dry = %w[--dry-run=client]

      assert_equal [0, "project/api created (dry run)\n", ''],
                   run_create('project', 'api', '--path', '~/x', '-n', 'work', *dry, runtime:)
      assert_equal [1, '', "error: groups \"home\" not found\n"],
                   run_create('project', 'api', '--path', '~/x', '-n', 'home', *dry, runtime:)
      assert_equal [2, '', "error: \"Bad\" is not a valid project name: #{Slipway::Names::RULE}\n#{HINT}"],
                   run_create('project', 'Bad', '--path', '~/x', *dry, runtime:)
      assert_equal [2, '', "error: \"Bad\" is not a valid group name: #{Slipway::Names::RULE}\n#{HINT}"],
                   run_create('project', 'api', '--path', '~/x', '-n', 'Bad', *dry, runtime:)
      assert_equal [2, '', "error: invalid label \"x\": expected KEY=VALUE\n#{HINT}"],
                   run_create('group', 'team', '--label', 'x', *dry, runtime:)
      assert_empty runtime.store.list(PROJECTS)
    end
  end

  def test_help_and_arity
    with_runtime do |runtime|
      status, out, err = run_create('--help', runtime:)

      assert_equal [0, ''], [status, err]
      assert_includes out, "Create a resource by name.\n\n"
      assert_includes out, "Usage:\n  slipway create TYPE NAME [flags]\n"
      assert_includes out, '      --label KEY=VALUE'
      assert_equal [2, '', "error: missing required argument \"NAME\"\n#{HINT}"], run_create('project', runtime:)
      assert_equal [2, '', "error: unexpected argument \"extra\"\n#{HINT}"],
                   run_create('project', 'hldr', 'extra', runtime:)
    end
  end

  private

  def run_create(*argv, runtime:, **)
    run_commands('create', *argv, runtime:, commands: [Slipway::Commands::Create], **)
  end
end
