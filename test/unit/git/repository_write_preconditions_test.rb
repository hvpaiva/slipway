# frozen_string_literal: true

require 'test_helper'
require 'slipway/git'
require 'tmpdir'

# Every state in which the fast-forward refuses before git merges, on real repositories.
class GitRepositoryWritePreconditionsTest < Minitest::Test
  include GitFixtures

  REFTABLE = Gem::Version.new('2.45')
  PSEUDOREFS = %w[CHERRY_PICK_HEAD REVERT_HEAD].freeze

  def setup
    @root = Dir.mktmpdir('slipway-write-preconditions-')
    @saved = replace_env(hermetic_env(@root))
    @runner = RecordingRunner.new
    @repo = Slipway::Git::Repository.new(runner: @runner)
  end

  def teardown
    restore_env(@saved)
    FileUtils.remove_entry(@root)
  end

  def test_each_state_is_refused_with_its_reason_before_git_merges
    { 'unborn' => ['Unborn', 'no commits yet'],
      'detached' => ['Detached', 'HEAD is detached at 5bbaee2'],
      'clean' => ['NoUpstream', 'main tracks no upstream'],
      'gone' => ['Gone', 'upstream origin/feature no longer exists'],
      'staged' => ['Dirty', '1 staged, 0 unstaged'],
      'unstaged' => ['Dirty', '0 staged, 1 unstaged'],
      'conflicted' => ['Conflicted', '1 unmerged path'],
      'diverged' => ['Diverged', '1 ahead, 1 behind origin/main'] }.each do |state, (reason, detail)|
      dir = build_repo(File.join(@root, state), state)

      assert_refused(dir, reason, detail)
    end
  end

  def test_a_dirty_tree_behind_its_upstream_is_refused
    dir = build_repo(File.join(@root, 'behind'), 'behind')
    write(dir, 'README.md', "changed\n")
    git!(dir, 'add', '--', 'README.md')
    write(dir, 'README.md', "changed again\n")

    assert_refused(dir, 'Dirty', '1 staged, 1 unstaged')
  end

  def test_a_branch_diverged_from_the_given_commit_names_it
    dir = build_repo(File.join(@root, 'diverged'), 'diverged')
    upstream = git!(dir, 'rev-parse', 'origin/main').chomp

    assert_refused(dir, 'Diverged', "1 ahead, 1 behind #{upstream[0, 7]}", onto: upstream)
  end

  def test_an_operation_in_progress_is_refused
    dir = build_repo(File.join(@root, 'stale'), 'stale')
    git!(dir, 'fetch', '-q')
    git!(dir, 'bisect', 'start')

    assert_refused(dir, 'InProgress', 'bisect in progress')
  end

  def test_in_progress_names_the_operation_git_waits_on
    assert_nil @repo.in_progress(build_repo(File.join(@root, 'clean'), 'clean'))
    assert_equal 'merge', @repo.in_progress(build_repo(File.join(@root, 'conflicted'), 'conflicted'))
    assert_equal 'rebase', @repo.in_progress(stopped_rebase)
    assert_equal 'git am session', @repo.in_progress(stopped_am)
  end

  # Git would check out the new tree and write the index before it found the lock.
  def test_a_lock_left_on_the_branch_is_busy_and_stays
    %w[HEAD.lock refs/heads/main.lock].each do |lock|
      dir = fetched_stale(lock.tr('/', '-'))
      FileUtils.touch(File.join(dir, '.git', lock))

      assert_refused(dir, 'Busy', "another git process holds #{lock}, or one left it behind")
      assert_empty git!(dir, 'status', '--porcelain')
      assert_path_exists File.join(dir, '.git', lock)
    end
  end

  def test_a_lock_left_on_a_reftable_repository_is_busy_and_stays
    dir = reftable_stale('reftable-lock')
    lock = File.join(dir, '.git', 'reftable', 'tables.list.lock')
    FileUtils.touch(lock)

    assert_refused(dir, 'Busy', 'another git process holds reftable/tables.list.lock, or one left it behind')
    assert_path_exists lock
  end

  def test_a_stopped_cherry_pick_or_revert_is_in_progress_once_the_tree_is_clean
    %w[cherry-pick revert].each do |command|
      dir = stopped(fetched_stale(command), command, 'side')
      git!(dir, 'checkout', 'HEAD', '--', 'README.md')

      assert_refused(dir, 'InProgress', "#{command} in progress")
    end
  end

  # A reset drops the pseudoref of the step that stopped; the steps left keep the operation open.
  def test_a_sequence_of_picks_or_reverts_stays_in_progress_after_a_reset
    %w[cherry-pick revert].each do |command|
      dir = stopped(fetched_stale("#{command}-sequence"), command, 'side', 'side~1')
      git!(dir, 'reset', '-q', '--hard')

      refute(PSEUDOREFS.any? { git(dir, 'rev-parse', '-q', '--verify', it).last.success? })
      assert_refused(dir, 'InProgress', "#{command} in progress")
    end
  end

  def test_a_stopped_cherry_pick_or_revert_in_a_reftable_repository_is_in_progress
    %w[cherry-pick revert].each do |command|
      dir = stopped(reftable_stale("reftable-#{command}"), command, 'side')
      git!(dir, 'checkout', 'HEAD', '--', 'README.md')

      assert_refused(dir, 'InProgress', "#{command} in progress")
    end
  end

  def test_a_missing_directory_is_missing_before_any_check
    assert_raises(Slipway::Git::MissingPath) { @repo.fast_forward(File.join(@root, 'nothing')) }
    assert_raises(Slipway::Git::MissingPath) { @repo.in_progress(File.join(@root, 'nothing')) }
    assert_empty @runner.commands
  end

  private

  def assert_refused(dir, reason, detail, onto: Slipway::Git::Repository::UPSTREAM)
    before = git(dir, 'rev-parse', '--verify', '-q', 'HEAD').first
    @runner.commands.clear

    error = assert_raises(Slipway::Git::Blocked, dir) { @repo.fast_forward(dir, onto:) }

    assert_equal [reason, "#{dir}: #{detail}"], [error.reason, error.message]
    assert_equal before, git(dir, 'rev-parse', '--verify', '-q', 'HEAD').first
    refute(@runner.commands.any? { it.include?('merge') }, dir)
  end

  def fetched_stale(name)
    dir = build_repo(File.join(@root, name), 'stale')
    git!(dir, 'fetch', '-q')
    dir
  end

  # The stale state, one behind origin/main, in a clone that keeps its refs in reftable.
  def reftable_stale(name)
    skip 'git before 2.45 cannot create a reftable repository' if GitEnv.version < REFTABLE
    origin = "#{build_repo(File.join(@root, "#{name}-files"), 'stale')}-origin.git"
    dir = File.join(@root, name)
    git!(@root, 'clone', '-q', '--ref-format=reftable', '--', origin, dir)
    git!(dir, 'reset', '-q', '--hard', 'HEAD~1')
    dir
  end

  # The side branch rewrites the readme twice, so its second commit, picked or reverted on main,
  # conflicts and main neither moves nor gains a commit.
  def stopped(dir, command, *revisions)
    git!(dir, 'switch', '-q', '-c', 'side')
    commit(dir, 'README.md', "first\n", 'rewrite the readme')
    commit(dir, 'README.md', "second\n", 'rewrite the readme again')
    git!(dir, 'switch', '-q', 'main')
    _, _, status = git(dir, command, '--no-edit', *revisions)
    raise "#{command} in #{dir} did not stop" if status.success?

    dir
  end

  # A rebase whose --exec step fails stops with the tree clean and HEAD detached.
  def stopped_rebase
    dir = build_repo(File.join(@root, 'rebase'), 'diverged')
    git(dir, 'rebase', '--exec', 'false', 'origin/main')
    dir
  end

  # A patch whose context no longer matches stops git am, which keeps the branch checked out.
  def stopped_am
    dir = build_repo(File.join(@root, 'am'), 'clean')
    git!(dir, 'switch', '-q', '-c', 'patch')
    commit(dir, 'README.md', "patched\n", 'patch the readme')
    patch = git!(dir, 'format-patch', '-1', '--stdout')
    git!(dir, 'switch', '-q', 'main')
    commit(dir, 'README.md', "rewritten\n", 'rewrite the readme')
    File.write(File.join(@root, 'readme.patch'), patch)
    git(dir, 'am', File.join(@root, 'readme.patch'))
    dir
  end
end
