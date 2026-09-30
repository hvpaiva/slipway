# frozen_string_literal: true

require 'shellwords'
require 'test_helper'

class CreateFromDirIntegrationTest < Minitest::Test
  include IntegrationHelper

  DIFFERENT_OWNER = { 'GIT_TEST_ASSUME_DIFFERENT_OWNER' => '1' }.freeze

  def test_clones_under_a_directory_are_registered_once_with_their_origin
    with_home do |env|
      clones(env)
      status, out, err = slipway('create', 'project', '--from-dir', '~/dev', '--depth', '2', env:)

      assert_equal [0, "project/hldr created\nproject/hldr-wt created\nproject/notes created\n" \
                       "project/tool created\n", ''], [status, out, err]
      assert_equal({ 'path' => '~/dev/hldr', 'remote' => 'https://example.com/hvpaiva/hldr.git' }, spec(env, 'hldr'))
      assert_equal({ 'path' => '~/dev/work/tool', 'remote' => 'git@example.com:hvpaiva/tool.git' }, spec(env, 'tool'))
      assert_equal "project/hldr unchanged\nproject/hldr-wt unchanged\nproject/notes unchanged\n" \
                   "project/tool unchanged\n", slipway!('create', 'project', '--from-dir', '~/dev', '--depth=2', env:)
    end
  end

  def test_the_registered_projects_read_as_the_clones_they_are
    with_home do |env|
      clones(env)
      slipway!('create', 'project', '--from-dir', '~/dev', env:)

      assert_table [%w[NAME BRANCH STATUS FETCHED AGE], ['hldr', 'main', 'Clean', '<never>', :age],
                    ['hldr-wt', 'wt', 'Clean', '<never>', :age], ['notes', 'main', 'Clean', '<never>', :age]],
                   slipway!('get', 'projects', env:)
      refute_includes File.read(File.join(data_home(env), 'projects', 'default', 'hldr.yaml')), 's3cret'
    end
  end

  def test_a_dry_run_prints_a_list_that_apply_registers
    with_home do |env|
      clones(env)
      manifests = slipway!('create', 'project', '--from-dir', '~/dev', '--dry-run=client', '-o', 'yaml', env:)

      refute_path_exists data_home(env)
      assert_match(/\Akind: List\nitems:\n/, manifests)
      assert_equal "project/hldr created\nproject/hldr-wt created\nproject/notes created\n",
                   slipway!('apply', '-f', '-', env:, stdin: manifests)
      assert_equal 'git@example.com:hvpaiva/notes.git', spec(env, 'notes')['remote']
    end
  end

  def test_an_origin_with_a_password_in_scp_form_is_left_out_without_being_printed
    with_home do |env|
      dir = File.join(env['HOME'], 'dev', 'leaky')
      build_repo(dir, 'clean')
      git!(dir, 'remote', 'add', 'origin', 'ci:s3cret@example.com:o/leaky.git')
      status, out, err = slipway('create', 'project', '--from-dir', '~/dev/leaky', env:)

      assert_equal [0, "project/leaky created\n"], [status, out]
      assert_equal 'warning: ~/dev/leaky: spec.remote left out: origin must not embed credentials; use a credential ' \
                   "helper\n", err
      assert_equal({ 'path' => '~/dev/leaky' }, spec(env, 'leaky'))
    end
  end

  # git config reads a repository it distrusts as one without an origin.
  def test_a_repository_git_distrusts_is_not_registered_as_one_without_an_origin
    with_home do |env|
      dir = build_repo(File.join(env['HOME'], 'dev', 'theirs'), 'clean')
      status, out, err = slipway('create', 'project', '--from-dir', '~/dev', env: env.merge(DIFFERENT_OWNER))

      assert_equal [1, ''], [status, out]
      assert_equal "error: ~/dev/theirs: repository has dubious ownership. Run 'git config --global --add " \
                   "safe.directory #{Shellwords.escape(dir)}' to trust it.\n", err
    end
  end

  private

  # hldr has a token in its origin and a linked worktree next to it; tool sits one level deeper;
  # a symbolic link and a plain directory are not repositories to register.
  def clones(env)
    dev = File.join(env['HOME'], 'dev')
    hldr = build_repo(File.join(dev, 'hldr'), 'clean')
    git!(hldr, 'remote', 'add', 'origin', 'https://ci:s3cret@example.com/hvpaiva/hldr.git')
    git!(hldr, 'worktree', 'add', '-q', '-b', 'wt', File.join(dev, 'hldr-wt'))
    { 'notes' => 'notes', 'work/tool' => 'tool' }.each do |path, name|
      git!(build_repo(File.join(dev, path), 'clean'), 'remote', 'add', 'origin', "git@example.com:hvpaiva/#{name}.git")
    end
    build_repo(File.join(dev, 'plain'), 'plain_dir')
    outside = build_repo(File.join(env['HOME'], 'outside'), 'clean')
    File.symlink(outside, File.join(dev, 'linked'))
  end

  def spec(env, name)
    Psych.safe_load_file(File.join(data_home(env), 'projects', 'default', "#{name}.yaml"))['spec']
  end
end
