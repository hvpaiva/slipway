# frozen_string_literal: true

require 'test_helper'

class DeleteIntegrationTest < Minitest::Test
  include IntegrationHelper

  def registry(env)
    seed(env, manifest('Group', 'work'),
         manifest('Project', 'clean', path: repo(env, 'clean')),
         manifest('Project', 'gone', path: repo(env, 'gone', nil)),
         manifest('Project', 'api', group: 'work', path: repo(env, 'api', nil)),
         manifest('Project', 'web', group: 'work', path: repo(env, 'web', nil)))
  end

  def test_deletes_a_project_registration_and_leaves_the_repository_alone
    with_home do |env|
      registry(env)
      status, out, err = slipway('delete', 'project', 'clean', env:)

      assert_equal [0, "project \"clean\" deleted from default group\n", ''], [status, out, err]
      refute_path_exists File.join(data_home(env), 'projects', 'default', 'clean.yaml')
      assert_path_exists File.join(env['HOME'], 'dev', 'clean', '.git')
      assert_equal [1, '', "error: projects \"clean\" not found\n"], slipway('delete', 'project', 'clean', env:)
    end
  end

  def test_deleting_a_group_cascades_to_its_projects
    with_home do |env|
      registry(env)
      status, out, err = slipway('delete', 'group', 'work', env:)

      assert_equal [0, "group \"work\" deleted\n", ''], [status, out, err]
      refute_path_exists File.join(data_home(env), 'groups', 'work.yaml')
      refute_path_exists File.join(data_home(env), 'projects', 'work')
      assert_equal [0, '', "No resources found in work group.\n"], slipway('get', 'projects', '-n', 'work', env:)
      assert_equal "project/clean\nproject/gone\n", slipway!('get', 'projects', '-A', '-o', 'name', env:)
    end
  end

  def test_dry_run_prints_the_line_without_deleting
    with_home do |env|
      registry(env)
      status, out, err = slipway('delete', 'projects', 'api', 'web', '-n', 'work', '--dry-run', env:)

      assert_equal [0, "project \"api\" deleted from work group (dry run)\nproject \"web\" deleted from work group " \
                       "(dry run)\n", ''], [status, out, err]
      assert_equal "project/api\nproject/web\n", slipway!('get', 'projects', '-n', 'work', '-o', 'name', env:)
    end
  end

  def test_every_name_is_resolved_before_anything_is_deleted
    with_home do |env|
      registry(env)
      status, out, err = slipway('delete', 'projects', 'gone', 'nothere', env:)

      assert_equal [1, '', "error: projects \"nothere\" not found\n"], [status, out, err]
      assert_equal "project/gone\n", slipway!('get', 'project', 'gone', '-o', 'name', env:)
    end
  end

  def test_ignore_not_found_skips_missing_names
    with_home do |env|
      registry(env)
      status, out, err = slipway('delete', 'projects', 'gone', 'nothere', '--ignore-not-found', env:)

      assert_equal [0, "project \"gone\" deleted from default group\n", ''], [status, out, err]
      assert_equal [0, '', ''], slipway('delete', 'project', 'gone', '--ignore-not-found', env:)
    end
  end

  def test_the_default_group_cannot_be_deleted
    with_home do |env|
      registry(env)

      assert_equal [1, '', "error: the default group cannot be deleted\n"], slipway('delete', 'group', 'default', env:)
      assert_equal [1, '', "error: the default group cannot be deleted\n"],
                   slipway('delete', 'groups', 'work', 'default', env:)
      assert_equal "group/default\ngroup/work\n", slipway!('get', 'groups', '-o', 'name', env:)
    end
  end

  def test_a_name_is_required
    with_home do |env|
      assert_equal [2, '', "error: resource(s) were provided, but no name was specified\n" \
                           "See 'slipway delete --help' for usage.\n"],
                   slipway('delete', 'project', env:)
    end
  end
end
