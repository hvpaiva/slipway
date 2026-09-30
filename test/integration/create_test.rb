# frozen_string_literal: true

require 'test_helper'

class CreateIntegrationTest < Minitest::Test
  include IntegrationHelper

  def test_creates_a_group_and_refuses_a_second_one_with_the_same_name
    with_home do |env|
      status, out, err = slipway('create', 'group', 'work', '--description', 'Day job', env:)

      assert_equal [0, "group/work created\n", ''], [status, out, err]
      assert_path_exists File.join(data_home(env), 'groups', 'work.yaml')

      status, out, err = slipway('create', 'group', 'work', env:)

      assert_equal [1, '', "error: group \"work\" already exists\n"], [status, out, err]
    end
  end

  def test_creates_a_project_in_the_default_group_which_appears_on_demand
    with_home do |env|
      path = repo(env, 'clean')
      status, out, err = slipway('create', 'project', 'clean', '--path', path, '--label', 'lang=rust',
                                 '--description', 'A clean one', env:)

      assert_equal [0, "project/clean created\n", ''], [status, out, err]
      assert_path_exists File.join(data_home(env), 'projects', 'default', 'clean.yaml')
      assert_path_exists File.join(data_home(env), 'groups', 'default.yaml')
      assert_equal "project/clean\n", slipway!('get', 'project', 'clean', '-o', 'name', env:)
    end
  end

  def test_the_manifest_on_disk_stores_the_path_as_written
    with_home do |env|
      slipway!('create', 'group', 'work', env:)
      slipway!('create', 'project', 'api', '--path', '~/work/api', '-n', 'work', '--label', 'lang=go', env:)
      manifest = Psych.safe_load_file(File.join(data_home(env), 'projects', 'work', 'api.yaml'))

      assert_equal %w[kind metadata spec], manifest.keys
      assert_equal({ 'name' => 'api', 'group' => 'work', 'labels' => { 'lang' => 'go' } },
                   manifest['metadata'].except('creationTimestamp'))
      assert_match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\z/, manifest['metadata']['creationTimestamp'])
      assert_equal({ 'path' => '~/work/api' }, manifest['spec'])
    end
  end

  def test_a_project_needs_an_existing_group
    with_home do |env|
      status, out, err = slipway('create', 'project', 'x', '--path', '~/dev/x', '-n', 'nope', env:)

      assert_equal [1, '', "error: groups \"nope\" not found\n"], [status, out, err]
      refute_path_exists File.join(data_home(env), 'projects')
    end
  end

  def test_a_project_needs_a_path_and_a_group_refuses_one
    with_home do |env|
      status, out, err = slipway('create', 'project', 'nopath', env:)

      assert_equal 2, status
      assert_empty out
      assert_equal "error: required flag(s) \"--path\" not set\nSee 'slipway create --help' for usage.\n", err

      status, _, err = slipway('create', 'group', 'g2', '--path', '/x', env:)

      assert_equal 2, status
      assert_equal "error: flag --path applies to projects only\nSee 'slipway create --help' for usage.\n", err
    end
  end

  def test_dry_run_checks_the_arguments_without_writing
    with_home do |env|
      status, out, err = slipway('create', 'project', 'dry', '--path', '~/dev/dry', '--dry-run', env:)

      assert_equal [0, "project/dry created (dry run)\n", ''], [status, out, err]
      refute_path_exists data_home(env)

      status, _, err = slipway('create', 'project', 'dry', '--path', '~/dev/dry', '-n', 'nope', '--dry-run',
                               env:)

      assert_equal [1, "error: groups \"nope\" not found\n"], [status, err]
    end
  end

  def test_a_relative_path_is_stored_resolved_against_the_current_directory
    with_home do |env|
      dir = File.join(env['HOME'], 'dev', 'here')
      build_repo(dir, 'clean')
      status, out, err = slipway('create', 'project', 'here', '--path', '.', env:, chdir: dir)

      assert_equal [0, "project/here created\n", ''], [status, out, err]
      manifest = File.read(File.join(data_home(env), 'projects', 'default', 'here.yaml'))

      assert_includes manifest, "path: \"#{File.realpath(dir)}\"\n"
      assert_equal 'Clean', table(slipway!('get', 'projects', env:)).last[2]
    end
  end

  def test_a_tilde_path_is_kept_as_written_and_an_empty_one_is_refused
    with_home do |env|
      slipway!('create', 'project', 'tilde', '--path', '~/dev/tilde', env:)
      status, out, err = slipway('create', 'project', 'empty', '--path', '', env:)

      assert_includes File.read(File.join(data_home(env), 'projects', 'default', 'tilde.yaml')), 'path: "~/dev/tilde"'
      assert_equal [2, '', "error: flag --path must not be empty\nSee 'slipway create --help' for usage.\n"],
                   [status, out, err]
    end
  end

  # The C locale labels the argument US-ASCII; the manifest still holds the UTF-8 the user typed.
  def test_remote_and_branch_land_in_the_manifest_on_disk
    with_home do |env|
      remote = "file:///srv/jo\u00e3o/hldr.git"
      status, out, err = slipway('create', 'project', 'hldr', '--path', '~/dev/hldr', '--remote', remote,
                                 '--branch', 'release/1.x', env:)
      manifest = Psych.safe_load_file(File.join(data_home(env), 'projects', 'default', 'hldr.yaml'))

      assert_equal [0, "project/hldr created\n", ''], [status, out, err]
      assert_equal({ 'path' => '~/dev/hldr', 'remote' => remote, 'branch' => 'release/1.x' }, manifest['spec'])
    end
  end

  def test_names_follow_rfc1123
    with_home do |env|
      status, out, err = slipway('create', 'project', 'Bad_Name', '--path', '~/dev/x', env:)

      assert_equal 2, status
      assert_empty out
      assert_equal 'error: "Bad_Name" is not a valid project name: lowercase letters, digits and dashes, ' \
                   "starting and ending with a letter or digit, at most 63 characters\n" \
                   "See 'slipway create --help' for usage.\n", err
    end
  end

  def test_slipway_data_home_moves_the_registry
    with_home do |env|
      data = File.join(env['HOME'], 'elsewhere')
      slipway!('create', 'group', 'work', env: env.merge('SLIPWAY_DATA_HOME' => data))

      assert_path_exists File.join(data, 'groups', 'work.yaml')
      refute_path_exists data_home(env)
      assert_equal "No resources found.\n", slipway('get', 'groups', env:).last
    end
  end
end
