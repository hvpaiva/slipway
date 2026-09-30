# frozen_string_literal: true

require 'test_helper'
require 'slipway/git'
require 'tmpdir'

class GitRepositoryFetchedAtTest < Minitest::Test
  include GitFixtures

  def setup
    @root = Dir.mktmpdir('slipway-fetched-at-')
    @saved = replace_env(hermetic_env(@root))
    @repo = Slipway::Git::Repository.new(protocols: %w[file])
  end

  def teardown
    restore_env(@saved)
    FileUtils.remove_entry(@root)
  end

  def test_fetched_at_is_nil_before_the_first_fetch_and_the_fetch_head_time_after
    dir = fixture('stale')

    assert_nil @repo.fetched_at(dir)

    @repo.fetch(dir, prune: false)
    fetched = @repo.fetched_at(dir)

    assert_equal File.mtime(File.join(dir, '.git', 'FETCH_HEAD')).utc, fetched
    assert_predicate fetched, :utc?
  end

  def test_fetched_at_is_nil_after_a_fetch_that_failed
    dir = fixture('stale')
    @repo.fetch(dir, prune: false)

    assert_raises(Slipway::Git::ProtocolNotAllowed) do
      Slipway::Git::Repository.new(protocols: %w[ssh]).fetch(dir, prune: false)
    end
    assert_nil @repo.fetched_at(dir)
  end

  def test_fetched_at_reads_a_git_directory_without_running_git
    dir = fixture('stale')
    @repo.fetch(dir, prune: false)
    repo = Slipway::Git::Repository.new(runner: Slipway::Git::Runner.new(binary: 'slipway-missing-git'))

    assert_equal @repo.fetched_at(dir), repo.fetched_at(dir)
  end

  def test_a_fetch_in_a_linked_worktree_dates_the_whole_repository
    dir, worktree = linked_worktree

    assert_nil @repo.fetched_at(worktree)

    @repo.fetch(worktree, prune: false)

    assert_instance_of Time, @repo.fetched_at(worktree)
    assert_equal @repo.fetched_at(worktree), @repo.fetched_at(dir)
  end

  def test_a_fetch_in_the_main_worktree_dates_a_linked_one
    dir, worktree = linked_worktree
    @repo.fetch(dir, prune: false)

    assert_instance_of Time, @repo.fetched_at(dir)
    assert_equal @repo.fetched_at(dir), @repo.fetched_at(worktree)
  end

  def test_the_newest_fetch_head_among_the_worktrees_wins
    dir, worktree = linked_worktree
    @repo.fetch(dir, prune: false)
    @repo.fetch(worktree, prune: false)
    File.utime(Time.utc(2026, 1, 1), Time.utc(2026, 1, 1), File.join(dir, '.git', 'FETCH_HEAD'))
    newest = File.mtime(File.join(dir, '.git', 'worktrees', 'worktree', 'FETCH_HEAD')).utc

    assert_equal [newest, newest], [@repo.fetched_at(dir), @repo.fetched_at(worktree)]
  end

  def test_fetched_at_of_a_missing_path_or_a_plain_directory_raises
    assert_raises(Slipway::Git::MissingPath) { @repo.fetched_at(File.join(@root, 'missing')) }
    assert_raises(Slipway::Git::NotARepository) { @repo.fetched_at(fixture('plain_dir')) }
  end

  private

  def fixture(state) = build_repo(File.join(@root, state), state)

  def linked_worktree
    dir = fixture('stale')
    worktree = File.join(@root, 'worktree')
    git!(dir, 'worktree', 'add', '-q', '-b', 'side', worktree)
    [dir, worktree]
  end
end
