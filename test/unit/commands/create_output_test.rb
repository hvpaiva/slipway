# frozen_string_literal: true

require 'test_helper'
require 'json'

class CreateOutputTest < Minitest::Test
  include CommandsHelper

  PROJECTS = Slipway::Resources.resolve('projects')
  HINT = "See 'slipway create --help' for usage.\n"

  def test_output_name_prints_the_resource_instead_of_the_result_line
    with_runtime do |runtime|
      assert_equal [0, "project/hldr\n", ''],
                   run_create('project', 'hldr', '--path', '~/dev/hldr', '-o', 'name', runtime:)
      assert_equal [0, "group/work\n", ''], run_create('group', 'work', '--output=name', runtime:)
      assert_equal %w[hldr], runtime.store.names(PROJECTS)
    end
  end

  def test_output_yaml_prints_the_manifest_as_it_was_written
    with_runtime do |runtime|
      status, out, err = run_create('project', 'hldr', '--path', '~/dev/hldr', '--label', 'lang=rust', '-o', 'yaml',
                                    runtime:)

      assert_equal [0, ''], [status, err]
      assert_equal Slipway::Manifest.dump(runtime.store.find(PROJECTS, 'hldr')), out
      assert_includes out, "creationTimestamp: '2026-09-29T09:00:00Z'\n"
    end
  end

  def test_a_dry_run_prints_a_manifest_apply_takes_and_writes_nothing
    with_runtime do |runtime|
      status, out, err = run_create('project', 'hldr', '--path', '~/dev/hldr', '--remote', 'git@h:o/r.git',
                                    '--dry-run', '-o', 'json', runtime:)

      assert_equal [0, ''], [status, err]
      assert_equal({ 'kind' => 'Project', 'metadata' => { 'name' => 'hldr', 'group' => 'default', 'labels' => {} },
                     'spec' => { 'path' => '~/dev/hldr', 'remote' => 'git@h:o/r.git' } }, JSON.parse(out))
      assert_empty runtime.store.list(PROJECTS)
    end
  end

  def test_output_is_limited_to_the_formats_create_can_print
    with_runtime do |runtime|
      assert_equal [2, '', "error: invalid argument \"wide\" for --output: must be one of json, yaml, name\n#{HINT}"],
                   run_create('group', 'work', '-o', 'wide', runtime:)
    end
  end

  private

  def run_create(*argv, runtime:, **)
    run_commands('create', *argv, runtime:, commands: [Slipway::Commands::Create], **)
  end
end
