# frozen_string_literal: true

require 'test_helper'
require 'tmpdir'

class GitRepositoryInProgressTest < Minitest::Test
  include GitFixtures

  def setup
    @root = Dir.mktmpdir('slipway-progress-')
    @saved = replace_env(hermetic_env(@root))
    @repo = Slipway::Git::Repository.new
  end

  def teardown
    restore_env(@saved)
    FileUtils.remove_entry(@root)
  end

  def test_a_rebase_stopped_on_a_merge_is_a_rebase
    dir = rebase_stopped_on_a_merge

    assert_path_exists File.join(dir, '.git', 'MERGE_HEAD')
    assert_equal 'rebase', @repo.in_progress(dir)
  end

  def test_a_linked_worktree_is_asked_about_its_own_markers
    main = build_repo(File.join(@root, 'clean'), 'clean')
    linked = File.join(@root, 'linked')
    git!(main, 'worktree', 'add', '-q', '-b', 'side', linked)
    git!(linked, 'bisect', 'start')

    assert_equal 'bisect', @repo.in_progress(linked)
    assert_nil @repo.in_progress(main)
  end

  private

  # side and topic rewrite the readme differently and topic merges side, so --rebase-merges
  # replays both branches cleanly onto main and stops when it merges them again.
  def rebase_stopped_on_a_merge
    dir = build_repo(File.join(@root, 'rebase'), 'clean')
    git!(dir, 'switch', '-q', '-c', 'side')
    commit(dir, 'README.md', "side\n", 'rewrite the readme on side')
    git!(dir, 'switch', '-q', '-c', 'topic', 'main')
    commit(dir, 'README.md', "topic\n", 'rewrite the readme on topic')
    git(dir, 'merge', '-q', '--no-edit', 'side')
    commit(dir, 'README.md', "merged\n", 'merge side')
    git!(dir, 'switch', '-q', 'main')
    commit(dir, 'notes.txt', "notes\n", 'add notes')
    git!(dir, 'switch', '-q', 'topic')
    _, _, status = git(dir, 'rebase', '-q', '--rebase-merges', 'main')
    raise "the rebase in #{dir} did not stop" if status.success?

    dir
  end
end
