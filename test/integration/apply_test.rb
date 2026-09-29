# frozen_string_literal: true

require 'test_helper'

class ApplyIntegrationTest < Minitest::Test
  include IntegrationHelper

  def manifest_file(env, name, text)
    path = File.join(env['HOME'], 'manifests', name)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, text)
    path
  end

  def test_a_file_is_created_then_unchanged_then_configured
    with_home do |env|
      file = manifest_file(env, 'one.yaml', manifest('Project', 'applied', path: repo(env, 'applied')))

      assert_equal [0, "project/applied created\n", ''], slipway('apply', '-f', file, env:)
      assert_equal [0, "project/applied unchanged\n", ''], slipway('apply', '-f', file, env:)

      File.write(file, manifest('Project', 'applied', path: '~/dev/applied', description: 'now described'))

      assert_equal [0, "project/applied configured\n", ''], slipway('apply', '-f', file, env:)
      assert_equal 'now described', Psych.safe_load_file(File.join(data_home(env), 'projects', 'default',
                                                                   'applied.yaml')).dig('spec', 'description')
    end
  end

  def test_a_directory_applies_its_yaml_files_in_order_and_collects_every_error
    with_home do |env|
      manifest_file(env, 'dir/a.yaml', manifest('Group', 'fromdir'))
      manifest_file(env, 'dir/b.yml', "#{manifest('Project', 'p1', group: 'fromdir', path: '~/dev/p1')}---\n" \
                                      "kind: Project\nmetadata:\n  name: p2\nspec:\n  path: ~/dev/p2\n  bogus: 1\n")
      manifest_file(env, 'dir/c.yaml', "kind: Project\nmetadata:\n  name: p3\nspec: {}\n")
      manifest_file(env, 'dir/ignored.txt', manifest('Project', 'p4', path: '~/dev/p4'))
      FileUtils.mkdir_p(File.join(env['HOME'], 'manifests', 'dir', 'nested.yaml'))
      dir = File.join(env['HOME'], 'manifests', 'dir')
      status, out, err = slipway('apply', '-f', dir, env:)

      assert_equal 1, status
      assert_equal "group/fromdir created\nproject/p1 created\n", out
      assert_equal "error: #{dir}/b.yml:2: unknown field \"spec.bogus\"\n" \
                   "error: #{dir}/c.yaml: \"spec.path\" is required\n", err
      assert_equal "project/p1\n", slipway!('get', 'projects', '-n', 'fromdir', '-o', 'name', env:)
    end
  end

  def test_stdin_is_read_for_a_dash
    with_home do |env|
      status, out, err = slipway('apply', '-f', '-', env:, stdin: manifest('Group', 'piped'))

      assert_equal [0, "group/piped created\n", ''], [status, out, err]
      assert_equal [1, '', "error: no objects passed to apply\n"], slipway('apply', '-f', '-', env:, stdin: '')
      assert_equal [1, '', "error: STDIN: did not find expected ',' or ']' at line 1, column 7\n"],
                   slipway('apply', '-f', '-', env:, stdin: "kind: [\nx: 1\n")
    end
  end

  def test_several_files_apply_in_order
    with_home do |env|
      group = manifest_file(env, 'group.yaml', manifest('Group', 'work'))
      project = manifest_file(env, 'project.yaml', manifest('Project', 'api', group: 'work', path: '~/work/api'))

      assert_equal [0, "group/work created\nproject/api created\n", ''],
                   slipway('apply', '-f', group, '-f', project, env:)
    end
  end

  def test_a_missing_file_and_an_empty_directory_are_errors
    with_home do |env|
      missing = File.join(env['HOME'], 'manifests', 'missing.yaml')
      empty = File.join(env['HOME'], 'manifests', 'empty')
      FileUtils.mkdir_p(empty)

      assert_equal [1, '', "error: #{missing}: no such file\n"], slipway('apply', '-f', missing, env:)
      assert_equal [1, '', "error: #{empty}: no .yaml or .yml files\n"], slipway('apply', '-f', empty, env:)
    end
  end

  def test_dry_run_reports_what_would_change_without_writing
    with_home do |env|
      api = manifest('Project', 'api', group: 'work', path: '~/work/api')
      file = manifest_file(env, 'one.yaml', "#{manifest('Group', 'work')}#{api}")
      status, out, err = slipway('apply', '-f', file, '--dry-run=client', env:)

      assert_equal [0, "group/work created (dry run)\nproject/api created (dry run)\n", ''], [status, out, err]
      refute_path_exists data_home(env)

      slipway!('apply', '-f', file, env:)

      assert_equal "group/work unchanged (dry run)\nproject/api unchanged (dry run)\n",
                   slipway!('apply', '-f', file, '--dry-run=client', env:)
    end
  end

  def test_a_project_without_a_group_lands_in_the_current_group
    with_home do |env|
      file = manifest_file(env, 'one.yaml', manifest('Project', 'api', path: '~/work/api'))
      slipway!('create', 'group', 'work', env:)

      assert_equal [0, "project/api created\n", ''], slipway('apply', '-f', file, '-n', 'work', env:)
      assert_equal [1, '', "error: #{file}: group \"nope\" not found\n"],
                   slipway('apply', '-f', file, '-n', 'nope', env:)
      assert_equal "project/api\n", slipway!('get', 'projects', '-n', 'work', '-o', 'name', env:)
    end
  end

  def test_the_filename_flag_is_required
    with_home do |env|
      assert_equal [2, '', "error: required flag(s) \"--filename\" not set\nSee 'slipway apply --help' for usage.\n"],
                   slipway('apply', env:)
    end
  end
end
