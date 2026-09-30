# frozen_string_literal: true

require 'test_helper'

class DiffIntegrationTest < Minitest::Test
  include IntegrationHelper

  NOTES = 'git@github.com:hvpaiva/notes.git'

  def test_a_branch_behind_its_upstream_will_be_fast_forwarded_and_exits_three
    with_home do |env|
      seed(env, manifest('Project', 'hldr', path: repo(env, 'hldr', 'behind')))

      assert_equal [3, "project/hldr\n  Behind: 1 commit behind origin/main; sync will fast-forward\n", ''],
                   slipway('diff', env:)
    end
  end

  def test_a_project_that_matches_its_manifest_prints_nothing_and_exits_zero
    with_home do |env|
      seed(env, manifest('Project', 'hldr', path: repo(env, 'hldr', 'synced'), branch: 'main'))

      assert_equal [0, '', ''], slipway('diff', 'hldr', env:)
      assert_equal [0, '', ''], slipway('diff', 'project/hldr', env:)
    end
  end

  def test_local_changes_block_the_fast_forward_and_name_the_command_that_shows_them
    with_home do |env|
      path = repo(env, 'hldr', 'behind')
      File.write(File.join(env['HOME'], 'dev', 'hldr', 'README.md'), "hello\nchanged\n")
      seed(env, manifest('Project', 'hldr', path:))

      assert_equal [3, <<~TEXT, ''], slipway('diff', env:)
        project/hldr
          Behind: 1 commit behind origin/main
          Dirty: 1 unstaged; sync fast-forwards only a tree without staged or unstaged changes
            git -C ~/dev/hldr status
      TEXT
    end
  end

  def test_an_operation_in_progress_blocks_a_branch_that_would_be_fast_forwarded
    with_home do |env|
      path = repo(env, 'hldr', 'behind')
      git!(File.join(env['HOME'], 'dev', 'hldr'), 'bisect', 'start')
      seed(env, manifest('Project', 'hldr', path:))

      assert_equal [3, <<~TEXT, ''], slipway('diff', env:)
        project/hldr
          Behind: 1 commit behind origin/main
          InProgress: a bisect is in progress
            git -C ~/dev/hldr status
      TEXT
    end
  end

  def test_an_origin_other_than_the_manifest_remote_is_reported_with_the_command_that_matches_it
    with_home do |env|
      seed(env, manifest('Project', 'notes', path: repo(env, 'notes', 'synced'), remote: NOTES))
      origin = File.join(env['HOME'], 'dev', 'notes-origin.git')

      assert_equal [3, <<~TEXT, ''], slipway('diff', env:)
        project/notes
          Remote: origin is #{origin}, manifest says #{NOTES}; sync never changes a remote
            git -C ~/dev/notes remote set-url origin #{NOTES}
      TEXT
    end
  end

  def test_a_missing_project_names_the_clone_its_manifest_allows
    with_home do |env|
      seed(env, manifest('Project', 'dotfiles', path: repo(env, 'dotfiles', nil), remote: NOTES))

      assert_equal [3, <<~TEXT, ''], slipway('diff', env:)
        project/dotfiles
          Missing: no directory at ~/dev/dotfiles
            git clone -- #{NOTES} ~/dev/dotfiles
      TEXT
    end
  end

  def test_an_unreadable_manifest_is_warned_about_and_exits_one_even_when_another_project_differs
    with_home do |env|
      seed(env, manifest('Project', 'hldr', path: repo(env, 'hldr', 'synced')))
      File.write(File.join(data_home(env), 'projects', 'default', 'broken.yaml'), "kind: Project\nspec: {path: \n")

      synced = slipway('diff', env:)
      seed(env, manifest('Project', 'notes', path: repo(env, 'notes', 'behind')))
      behind = slipway('diff', env:)

      assert_equal [1, ''], synced.first(2)
      assert_match(/\Awarning: \S+broken\.yaml: /, synced.last)
      assert_equal 1, behind.first
      assert_equal "project/notes\n  Behind: 1 commit behind origin/main; sync will fast-forward\n", behind[1]
    end
  end

  def test_diff_writes_nothing_and_contacts_no_remote
    with_home do |env|
      dir = File.join(env['HOME'], 'dev', 'hldr')
      marker = File.join(env['HOME'], 'contacted')
      seed(env, manifest('Project', 'hldr', path: repo(env, 'hldr', 'behind')))
      git!(dir, 'remote', 'set-url', 'origin', 'ssh://git@forge.invalid/hldr.git')
      before = snapshot(dir)

      status, = slipway('diff', env: env.merge('GIT_SSH_COMMAND' => "touch #{marker}; false"))

      assert_equal 3, status
      assert_equal before, snapshot(dir)
      refute_path_exists marker
      refute_path_exists File.join(dir, '.git', 'FETCH_HEAD')
    end
  end

  private

  def snapshot(dir)
    [git!(dir, 'for-each-ref'), git!(dir, 'status', '--porcelain=v2', '--branch'),
     File.binread(File.join(dir, '.git', 'index'))]
  end
end
