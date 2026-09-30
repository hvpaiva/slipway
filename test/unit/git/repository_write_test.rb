# frozen_string_literal: true

require 'test_helper'
require 'slipway/git'
require 'tmpdir'

# The one write to a working tree, against real repositories whose origin moved on.
class GitRepositoryWriteTest < Minitest::Test
  include GitFixtures

  def setup
    @root = Dir.mktmpdir('slipway-write-')
    @saved = replace_env(hermetic_env(@root))
    @repo = Slipway::Git::Repository.new
  end

  def teardown
    restore_env(@saved)
    FileUtils.remove_entry(@root)
  end

  def test_a_fetched_stale_branch_moves_onto_its_upstream
    dir = fetched('stale')
    old = head(dir)
    upstream = git!(dir, 'rev-parse', 'origin/main').chomp

    move = @repo.fast_forward(dir)

    assert_equal Slipway::Git::FastForward.new(from: old, to: upstream, count: 1), move
    assert_equal [upstream, old], [head(dir), git!(dir, 'rev-parse', 'ORIG_HEAD').chomp]
    assert_equal [0, 0, true], [@repo.status(dir).behind, @repo.status(dir).ahead, @repo.status(dir).clean?]
  end

  def test_the_branch_reflog_names_slipway_as_the_mover
    dir = fetched('stale')

    @repo.fast_forward(dir)

    assert_equal 'slipway sync: Fast-forward', reflog(dir).first
  end

  def test_a_second_fast_forward_moves_nothing
    dir = fetched('stale')
    @repo.fast_forward(dir)
    entries = reflog(dir)

    move = @repo.fast_forward(dir)

    assert_equal Slipway::Git::FastForward.new(from: head(dir), to: head(dir), count: 0), move
    refute_predicate move, :moved?
    assert_equal entries, reflog(dir)
  end

  def test_an_untracked_file_out_of_the_way_does_not_block_and_is_kept
    dir = fetched('stale')
    write(dir, 'notes.txt', "u\n")

    assert_equal 1, @repo.fast_forward(dir).count
    assert_equal ["u\n", 1], [File.read(File.join(dir, 'notes.txt')), @repo.status(dir).untracked]
  end

  def test_a_branch_ahead_of_its_upstream_moves_nothing
    dir = build_repo(File.join(@root, 'ahead'), 'ahead')
    before = head(dir)

    assert_equal Slipway::Git::FastForward.new(from: before, to: before, count: 0), @repo.fast_forward(dir)
    assert_equal before, head(dir)
  end

  def test_a_full_object_name_moves_the_branch_that_far_and_no_further
    dir = build_repo(File.join(@root, 'stale'), 'stale')
    middle = head("#{dir}-other")
    push_change("#{dir}-other", 'c.txt', "c\n")
    git!(dir, 'fetch', '-q')

    move = @repo.fast_forward(dir, onto: middle, reflog_action: 'slipway rollout undo')

    assert_equal [middle, 1], [move.to, move.count]
    assert_equal [middle, 'slipway rollout undo: Fast-forward'], [head(dir), reflog(dir).first]
    assert_equal 1, @repo.fast_forward(dir).count
  end

  # A pushed side branch holds a commit that descends from HEAD but that main upstream never had.
  def test_a_full_object_name_the_upstream_lacks_is_off_upstream
    dir = build_repo(File.join(@root, 'stale'), 'stale')
    push_change("#{dir}-other", 'side.txt', "side\n", branch: 'side')
    git!(dir, 'fetch', '-q')
    side = git!(dir, 'rev-parse', 'origin/side').chomp
    before = head(dir)

    error = assert_raises(Slipway::Git::Blocked) { @repo.fast_forward(dir, onto: side) }

    assert_equal ['OffUpstream', "#{dir}: commit #{side[0, 7]} is not on origin/main"], [error.reason, error.message]
    assert_equal before, head(dir)
  end

  def test_an_object_name_that_is_no_commit_here_is_revision_not_found
    dir = fetched('stale')
    before = head(dir)
    blob = git!(dir, 'rev-parse', 'HEAD:README.md').chomp

    ['f' * 40, blob].each do |onto|
      error = assert_raises(Slipway::Git::Blocked) { @repo.fast_forward(dir, onto:) }

      assert_equal 'RevisionNotFound', error.reason
      assert_equal "#{dir}: commit #{onto} is not in this repository", error.message
    end
    assert_equal before, head(dir)
  end

  def test_an_untracked_file_the_incoming_commit_adds_is_left_alone
    dir = fetched('stale_untracked_overlap')
    before = head(dir)

    error = assert_raises(Slipway::Git::WouldOverwrite) { @repo.fast_forward(dir) }

    assert_equal "#{dir}: the incoming commits would overwrite untracked files", error.message
    assert_equal [before, "local b\n"], [head(dir), File.read(File.join(dir, 'b.txt'))]
    assert_equal 1, @repo.status(dir).behind
  end

  # The ignored content was never committed, so git would have no copy to restore it from.
  def test_an_ignored_file_or_directory_the_incoming_commit_replaces_is_left_alone
    { 'ignored-file' => 'b.txt', 'ignored-dir' => 'b.txt/kept' }.each do |name, local|
      dir = fetched('stale', name)
      FileUtils.mkdir_p(File.dirname(File.join(dir, local)))
      write(dir, local, "local\n")
      File.write(File.join(dir, '.git', 'info', 'exclude'), "b.txt\n", mode: 'a')
      before = head(dir)

      assert_raises(Slipway::Git::WouldOverwrite, name) { @repo.fast_forward(dir) }
      assert_equal [before, "local\n"], [head(dir), File.read(File.join(dir, local))], name
    end
  end

  def test_a_held_index_lock_is_busy_and_stays
    dir = fetched('index_lock')
    before = head(dir)

    error = assert_raises(Slipway::Git::Busy) { @repo.fast_forward(dir) }

    assert_equal 'Busy', error.reason
    assert_path_exists File.join(dir, '.git', 'index.lock')
    assert_equal before, head(dir)
  end

  # skip-worktree hides the change from git status, so only git's own check can see it.
  def test_a_local_change_status_does_not_show_is_kept
    dir = build_repo(File.join(@root, 'stale'), 'stale')
    push_change("#{dir}-other", 'README.md', "upstream\n")
    git!(dir, 'fetch', '-q')
    git!(dir, 'update-index', '--skip-worktree', 'README.md')
    write(dir, 'README.md', "mine\n")
    before = head(dir)

    assert_raises(Slipway::Git::WouldLoseChanges) { @repo.fast_forward(dir) }
    assert_equal [before, "mine\n"], [head(dir), File.read(File.join(dir, 'README.md'))]
  end

  def test_a_commit_made_between_the_checks_and_the_merge_is_not_fast_forward
    dir = fetched('stale')
    before = head(dir)
    repo = Slipway::Git::Repository.new(runner: Slipway::Git::Runner.new(binary: committing_git))

    error = assert_raises(Slipway::Git::NotFastForward) { repo.fast_forward(dir) }

    assert_equal "#{dir}: the branch cannot be fast-forwarded", error.message
    assert_equal before, git!(dir, 'rev-parse', 'HEAD~1').chomp
    assert_equal 'race', git!(dir, 'log', '-1', '--format=%s').chomp
  end

  # A smudge filter holds git inside the checkout, after it wrote .gitattributes, until the
  # deadline stops it.
  def test_a_move_stopped_at_the_deadline_keeps_the_branch_and_says_its_files_stay
    dir = build_repo(File.join(@root, 'stale'), 'stale')
    other = "#{dir}-other"
    write(other, '.gitattributes', "*.slow filter=slow\n")
    git!(other, 'add', '--', '.gitattributes')
    commit(other, 'f.slow', "slow\n", 'add a filtered file')
    git!(other, 'push', '-q', 'origin', 'main')
    git!(dir, 'fetch', '-q')
    git!(dir, 'config', 'filter.slow.smudge', 'sleep 10; cat')
    before = head(dir)
    repo = Slipway::Git::Repository.new(network_timeout: 1)

    error = assert_raises(Slipway::Git::WriteTimeout) { repo.fast_forward(dir) }

    assert_equal "#{dir}: git did not finish within 1 second; the files it had written stay in the working tree",
                 error.message
    assert_equal [before, true], [head(dir), File.exist?(File.join(dir, '.gitattributes'))]
  end

  private

  def fetched(state, name = state)
    dir = build_repo(File.join(@root, name), state)
    git!(dir, 'fetch', '-q')
    dir
  end

  def head(dir) = git!(dir, 'rev-parse', 'HEAD').chomp

  def reflog(dir) = git!(dir, 'reflog', 'show', '--format=%gs', 'refs/heads/main').lines(chomp: true)

  def push_change(clone, name, text, branch: 'main')
    git!(clone, 'checkout', '-q', '-B', branch)
    commit(clone, name, text, "change #{name}")
    git!(clone, 'push', '-q', 'origin', branch)
  end

  # Commits on the branch just before git merges, as a user working beside slipway would.
  def committing_git
    body = <<~SH
      case " $* " in
        *" merge "*) git -C "$2" -c user.name=Race -c user.email=race@example.com commit -q --allow-empty -m race ;;
      esac
      exec git "$@"
    SH
    File.join(fake_git(@root, body), 'git')
  end
end
