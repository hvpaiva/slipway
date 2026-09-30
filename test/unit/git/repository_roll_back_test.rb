# frozen_string_literal: true

require 'test_helper'
require 'slipway/git'
require 'tmpdir'

# The one reset slipway runs, against real repositories a fast-forward moved.
class GitRepositoryRollBackTest < Minitest::Test
  include GitFixtures

  def setup
    @root = Dir.mktmpdir('slipway-roll-back-')
    @saved = replace_env(hermetic_env(@root))
    @runner = RecordingRunner.new
    @repo = Slipway::Git::Repository.new(runner: @runner)
  end

  def teardown
    restore_env(@saved)
    FileUtils.remove_entry(@root)
  end

  def test_a_fast_forwarded_branch_moves_back_with_reset_keep_and_the_reflog_names_the_undo
    dir, old, new = synced_forward('stale')

    move = @repo.roll_back(dir, to: old)

    assert_equal Slipway::Git::MoveBack.new(from: new, to: old, count: 1), move
    assert_predicate move, :moved?
    assert_equal [old, 'slipway rollout undo: updating HEAD'], [head(dir), reflog(dir).first]
    assert_equal [1, 0], [@repo.status(dir).behind, @repo.status(dir).ahead]
    assert_equal ['reset', '--keep', '--quiet', '--no-recurse-submodules', old, '--'], resets.first.last(6)
    assert_equal 1, resets.size
  end

  def test_untracked_files_and_unstaged_changes_to_files_the_move_leaves_alone_are_kept
    dir, old, = synced_forward('stale')
    write(dir, 'notes.txt', "mine\n")
    write(dir, 'README.md', "hello\nchanged\n")

    @repo.roll_back(dir, to: old)

    assert_equal [old, "mine\n", "hello\nchanged\n"],
                 [head(dir), File.read(File.join(dir, 'notes.txt')), File.read(File.join(dir, 'README.md'))]
  end

  def test_a_staged_change_is_refused_because_reset_keep_would_drop_it_from_the_index
    dir, old, new = synced_forward('stale')
    write(dir, 'README.md', "hello\nstaged\n")
    git!(dir, 'add', 'README.md')
    write(dir, 'README.md', "hello\nedited\n")

    error = assert_raises(Slipway::Git::Blocked) { @repo.roll_back(dir, to: old) }

    assert_equal ['Dirty', "#{dir}: 1 staged, 1 unstaged"], [error.reason, error.message]
    assert_equal [new, [], "hello\nstaged\n"], [head(dir), resets, git!(dir, 'show', ':README.md')]
  end

  def test_a_branch_already_at_the_target_moves_nothing
    dir, _, new = synced_forward('stale')
    entries = reflog(dir)

    move = @repo.roll_back(dir, to: new)

    assert_equal Slipway::Git::MoveBack.new(from: new, to: new, count: 0), move
    refute_predicate move, :moved?
    assert_equal [entries, []], [reflog(dir), resets]
  end

  def test_a_commit_only_this_branch_holds_is_never_dropped
    dir, old, = synced_forward('stale')
    commit(dir, 'local.txt', "local\n", 'local work')
    before = head(dir)

    error = assert_raises(Slipway::Git::Blocked) { @repo.roll_back(dir, to: old) }

    assert_equal ['LocalCommits', "#{dir}: main has commits that are not on origin/main"], [error.reason, error.message]
    assert_equal [before, []], [head(dir), resets]
  end

  def test_a_target_off_the_history_of_the_branch_is_diverged
    dir, old, = synced_forward('stale')
    git!(dir, 'checkout', '-q', '-b', 'side', old)
    commit(dir, 'side.txt', "side\n", 'side work')
    side = head(dir)
    git!(dir, 'checkout', '-q', 'main')

    error = assert_raises(Slipway::Git::Blocked) { @repo.roll_back(dir, to: side) }

    assert_equal ['Diverged', "#{dir}: commit #{side[0, 7]} is not on the history of main"],
                 [error.reason, error.message]
    assert_empty resets
  end

  def test_a_local_change_to_a_file_the_move_rewrites_keeps_the_branch_and_the_file
    dir, old, new = synced_forward('stale')
    write(dir, 'b.txt', "edited\n")

    assert_raises(Slipway::Git::WouldLoseChanges) { @repo.roll_back(dir, to: old) }
    assert_equal [new, "edited\n"], [head(dir), File.read(File.join(dir, 'b.txt'))]
  end

  # reset --keep refuses an untracked file in the way but replaces an ignored one.
  def test_an_untracked_or_ignored_entry_where_the_move_restores_a_file_is_left_alone
    { 'untracked' => 'gone.txt', 'ignored' => 'gone.txt', 'ignored-parent' => 'docs' }.each do |name, local|
      dir, old, new = removed_upstream(name, local == 'docs' ? 'docs/guide.md' : 'gone.txt')
      write(dir, local, "local\n")
      File.write(File.join(dir, '.git', 'info', 'exclude'), "#{local}\n", mode: 'a') unless name == 'untracked'

      assert_raises(Slipway::Git::WouldOverwrite, name) { @repo.roll_back(dir, to: old) }
      assert_equal [new, "local\n"], [head(dir), File.read(File.join(dir, local))], name
    end
  end

  def test_a_symbolic_link_where_the_move_restores_a_directory_is_left_alone
    dir, old, new = removed_upstream('link', 'docs/guide.md')
    File.symlink(@root, File.join(dir, 'docs'))

    assert_raises(Slipway::Git::WouldOverwrite) { @repo.roll_back(dir, to: old) }
    assert_equal [new, @root], [head(dir), File.readlink(File.join(dir, 'docs'))]
  end

  def test_a_directory_where_the_move_restores_a_file_inside_it_does_not_block
    dir, old, = removed_upstream('kept', 'docs/guide.md')
    write(dir, 'notes.txt', "mine\n")

    @repo.roll_back(dir, to: old)

    assert_equal [old, "guide\n"], [head(dir), File.read(File.join(dir, 'docs', 'guide.md'))]
  end

  def test_a_detached_head_or_an_operation_in_progress_is_blocked_before_any_reset
    dir, old, = synced_forward('stale')
    git!(dir, 'checkout', '-q', '--detach')

    assert_equal 'Detached', assert_raises(Slipway::Git::Blocked) { @repo.roll_back(dir, to: old) }.reason
    git!(dir, 'checkout', '-q', 'main')
    File.write(File.join(dir, '.git', 'MERGE_HEAD'), "#{old}\n")

    assert_equal 'InProgress', assert_raises(Slipway::Git::Blocked) { @repo.roll_back(dir, to: old) }.reason
    assert_empty resets
  end

  def test_an_abbreviated_or_missing_target_is_refused
    dir, = synced_forward('stale')

    assert_raises(ArgumentError) { @repo.roll_back(dir, to: 'abc1234') }
    assert_equal 'RevisionNotFound', assert_raises(Slipway::Git::Blocked) { @repo.roll_back(dir, to: 'f' * 40) }.reason
    assert_empty resets
  end

  def test_a_move_stopped_at_the_deadline_keeps_the_branch
    dir, old, new = removed_upstream('slow', 'gone.slow')
    File.write(File.join(dir, '.git', 'info', 'attributes'), "*.slow filter=slow\n")
    git!(dir, 'config', 'filter.slow.smudge', 'sleep 10; cat')
    repo = Slipway::Git::Repository.new(network_timeout: 1)

    assert_raises(Slipway::Git::WriteTimeout) { repo.roll_back(dir, to: old) }
    assert_equal new, head(dir)
  end

  # Git applies submodule.recurse to reset, which would check out the submodule's own working tree.
  def test_a_move_back_leaves_a_submodule_where_it_was_under_submodule_recurse
    dir, old, sub, moved = with_submodule
    git!(dir, 'config', 'submodule.recurse', 'true')

    @repo.roll_back(dir, to: old)

    assert_equal [old, moved], [head(dir), head(sub)]
  end

  private

  # A branch whose last commit moves the gitlink of submodule "sub": the directory, the commit
  # before that move, the submodule's working tree and the commit it has checked out.
  def with_submodule
    dir = build_repo(File.join(@root, 'super'), 'synced')
    library = build_repo(File.join(@root, 'library'), 'clean')
    git!(dir, '-c', 'protocol.file.allow=always', 'submodule', 'add', '-q', '--', library, 'sub')
    git!(dir, 'commit', '-q', '-m', 'add sub')
    old = head(dir)
    sub = File.join(dir, 'sub')
    commit(sub, 'lib.txt', "lib\n", 'library work')
    git!(dir, 'commit', '-q', '-am', 'move sub')
    git!(dir, 'push', '-q', 'origin', 'main')
    [dir, old, sub, head(sub)]
  end

  # A stale clone after slipway's fast-forward: the directory, the commit before and after it.
  def synced_forward(state, name = state)
    dir = build_repo(File.join(@root, name), state)
    git!(dir, 'fetch', '-q')
    old = head(dir)
    @repo.fast_forward(dir)
    [dir, old, head(dir)]
  end

  # The fast-forward removes +path+, so a move back restores it.
  def removed_upstream(name, path)
    dir = build_repo(File.join(@root, name), 'synced')
    FileUtils.mkdir_p(File.dirname(File.join(dir, path)))
    commit(dir, path, "#{File.basename(path, '.*')}\n", "add #{path}")
    git!(dir, 'push', '-q', 'origin', 'main')
    other = "#{dir}-other"
    git!(@root, 'clone', '-q', '--', "#{dir}-origin.git", other)
    git!(other, 'rm', '-q', '--', path)
    git!(other, 'commit', '-q', '-m', "remove #{path}")
    git!(other, 'push', '-q', 'origin', 'main')
    git!(dir, 'fetch', '-q')
    old = head(dir)
    @repo.fast_forward(dir)
    [dir, old, head(dir)]
  end

  def resets = @runner.commands.select { it.include?('reset') }

  def head(dir) = git!(dir, 'rev-parse', 'HEAD').chomp

  def reflog(dir) = git!(dir, 'reflog', 'show', '--format=%gs', 'refs/heads/main').lines(chomp: true)
end
