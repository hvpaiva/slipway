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

  def test_a_pinned_project_is_compared_with_its_pin_and_never_moved_back_to_it
    with_home do |env|
      ahead = repo(env, 'ahead', 'ahead')
      dir = File.join(env['HOME'], 'dev', 'ahead')
      base, head = %w[HEAD~1 HEAD].map { git!(dir, 'rev-parse', it).chomp }
      seed(env, manifest('Project', 'ahead', path: ahead, revision: base),
           manifest('Project', 'lost', path: repo(env, 'lost', 'synced'), revision: 'f' * 40))

      assert_equal [3, <<~TEXT, ''], slipway('diff', env:)
        project/ahead
          Revision: HEAD is at #{head[0, 7]}, manifest pins #{base[0, 7]}
          PastRevision: main is past the pinned revision; sync never moves a branch back
            git -C ~/dev/ahead log --oneline #{base[0, 7]}..HEAD
        project/lost
          Revision: HEAD is at #{GetRegistry::HEAD}, manifest pins fffffff
          RevisionNotFound: spec.revision fffffff is not in this repository; fetch it or unpin
      TEXT
    end
  end

  # git peels a pin that names an annotated tag to the commit it tags. A pushed side branch holds a
  # commit that descends from HEAD, and sync never follows it there.
  def test_a_pin_on_a_tag_of_head_matches_and_one_the_upstream_lacks_is_blocked
    with_home do |env|
      side = build_repo(File.join(env['HOME'], 'dev', 'side'), 'stale')
      tagged = build_repo(File.join(env['HOME'], 'dev', 'tagged'), 'synced')
      pin = side_commit(side)
      seed(env, manifest('Project', 'side', path: '~/dev/side', revision: pin),
           manifest('Project', 'tagged', path: '~/dev/tagged', revision: annotated_tag(tagged)))
      head = git!(side, 'rev-parse', 'HEAD')[0, 7]
      pin = pin[0, 7]

      assert_equal [3, <<~TEXT, ''], slipway('diff', env:)
        project/side
          Revision: HEAD is at #{head}, manifest pins #{pin}
          OffUpstream: spec.revision #{pin} is not on origin/main; sync moves a branch only along its upstream
            git -C ~/dev/side log --oneline @{upstream}..#{pin}
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

  def annotated_tag(dir)
    git!(dir, 'tag', '-a', '-m', 'v1', 'v1')
    git!(dir, 'rev-parse', 'v1').chomp
  end

  def side_commit(dir)
    git!("#{dir}-other", 'checkout', '-q', '-b', 'side')
    git!("#{dir}-other", 'commit', '-q', '--allow-empty', '-m', 'side work')
    git!("#{dir}-other", 'push', '-q', 'origin', 'side')
    git!(dir, 'fetch', '-q')
    git!(dir, 'rev-parse', 'origin/side').chomp
  end

  def snapshot(dir)
    [git!(dir, 'for-each-ref'), git!(dir, 'status', '--porcelain=v2', '--branch'),
     File.binread(File.join(dir, '.git', 'index'))]
  end
end
