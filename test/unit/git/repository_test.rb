# frozen_string_literal: true

require 'test_helper'
require 'slipway/git'
require 'tmpdir'

# Runs the real git against the fixture repositories.
class GitRepositoryTest < Minitest::Test
  include GitFixtures

  FIRST_COMMIT = '5bbaee2c60e94db1f64d04925d8365eec25d449b'
  COMMIT_TIME = Time.utc(2023, 11, 14, 22, 13, 20)

  # A stand-in Runner that answers every call with one canned Result.
  class CannedRunner
    def initialize(status, err)
      @result = Slipway::Git::Runner::Result.new(status:, out: '', err:)
    end

    def run(*) = @result
  end

  def setup
    @root = Dir.mktmpdir('slipway-repo-')
    @saved = replace_env(hermetic_env(@root))
    @repo = Slipway::Git::Repository.new
  end

  def teardown
    restore_env(@saved)
    FileUtils.remove_entry(@root)
  end

  def test_building_clean_twice_yields_the_same_head
    first = build_repo(File.join(@root, 'one'), 'clean')
    second = build_repo(File.join(@root, 'two'), 'clean')

    assert_equal FIRST_COMMIT, git!(first, 'rev-parse', 'HEAD').strip
    assert_equal git!(first, 'rev-parse', 'HEAD'), git!(second, 'rev-parse', 'HEAD')
  end

  def test_clean
    dir = fixture('clean')

    assert_equal expected(dir), @repo.status(dir)
  end

  def test_staged
    dir = fixture('staged')

    assert_equal expected(dir, staged: 1), @repo.status(dir)
  end

  def test_unstaged
    dir = fixture('unstaged')

    assert_equal expected(dir, unstaged: 1), @repo.status(dir)
  end

  def test_untracked
    dir = fixture('untracked')

    assert_equal expected(dir, untracked: 1), @repo.status(dir)
  end

  def test_ahead
    dir = fixture('ahead')

    assert_equal expected(dir, upstream: 'origin/main', ahead: 1, behind: 0), @repo.status(dir)
  end

  def test_behind
    dir = fixture('behind')

    assert_equal expected(dir, upstream: 'origin/main', ahead: 0, behind: 1), @repo.status(dir)
  end

  def test_diverged
    dir = fixture('diverged')

    assert_equal expected(dir, upstream: 'origin/main', ahead: 1, behind: 1), @repo.status(dir)
  end

  def test_detached
    dir = fixture('detached')

    assert_equal expected(dir, branch: nil), @repo.status(dir)
  end

  def test_unborn
    dir = fixture('unborn')

    assert_equal Slipway::Git::Status.new(branch: 'main', head: nil), @repo.status(dir)
  end

  def test_conflicted
    dir = fixture('conflicted')

    assert_equal expected(dir, conflicted: 1), @repo.status(dir)
  end

  def test_gone
    dir = fixture('gone')

    assert_equal expected(dir, branch: 'feature', upstream: 'origin/feature', upstream_gone: true), @repo.status(dir)
  end

  def test_stash
    dir = fixture('stash')

    assert_equal expected(dir, stashes: 2), @repo.status(dir)
  end

  def test_status_expands_the_path
    fixture('clean')

    assert_equal 'main', @repo.status('~/clean').branch
  end

  def test_status_of_a_subdirectory_does_not_describe_the_enclosing_repository
    dir = fixture('untracked')
    sub = File.join(dir, 'sub')
    FileUtils.mkdir_p(sub)
    File.write(File.join(sub, 'deep.txt'), "deep\n")

    error = assert_raises(Slipway::Git::NotARepository) { @repo.status(sub) }

    assert_equal "#{sub}: not a git repository", error.message
    assert_equal expected(dir, untracked: 2), @repo.status(dir)
  end

  def test_last_commit_reads_every_field_in_utc
    dir = fixture('clean')

    commit = @repo.last_commit(dir)

    assert_equal FIRST_COMMIT, commit.sha
    assert_equal 40, commit.sha.length
    assert_equal FIRST_COMMIT[0, 7], commit.short
    assert_equal COMMIT_TIME, commit.time
    assert_predicate commit.time, :utc?
    assert_equal ['Fixture', 'fixture@example.com', 'initial commit'], [commit.author, commit.email, commit.subject]
  end

  def test_last_commit_follows_head_on_every_branch_state
    assert_equal 'local work', @repo.last_commit(fixture('ahead')).subject
    assert_equal 'diverging work', @repo.last_commit(fixture('diverged')).subject
    assert_equal 'main side', @repo.last_commit(fixture('conflicted')).subject
    assert_equal 'initial commit', @repo.last_commit(fixture('detached')).subject
  end

  def test_last_commit_is_nil_on_an_unborn_branch
    assert_nil @repo.last_commit(fixture('unborn'))
  end

  def test_remote_url_is_the_origin_url_or_nil
    ahead = fixture('ahead')

    assert_equal "#{ahead}-origin.git", @repo.remote_url(ahead)
    assert_nil @repo.remote_url(fixture('clean'))
  end

  def test_a_missing_path_raises_without_spawning_git
    missing = File.join(@root, 'missing')
    repo = Slipway::Git::Repository.new(runner: Slipway::Git::Runner.new(binary: 'slipway-missing-git'))

    error = assert_raises(Slipway::Git::MissingPath) { repo.status(missing) }

    assert_equal "#{missing}: no such directory", error.message
    assert_raises(Slipway::Git::MissingPath) { repo.last_commit(missing) }
    assert_raises(Slipway::Git::MissingPath) { repo.remote_url(missing) }
  end

  def test_a_file_is_a_missing_path
    file = File.join(fixture('clean'), 'README.md')

    assert_raises(Slipway::Git::MissingPath) { @repo.status(file) }
  end

  def test_a_plain_directory_is_not_a_repository
    dir = fixture('plain_dir')

    error = assert_raises(Slipway::Git::NotARepository) { @repo.status(dir) }

    assert_equal "#{dir}: not a git repository", error.message
    assert_raises(Slipway::Git::NotARepository) { @repo.last_commit(dir) }
    assert_nil @repo.remote_url(dir)
  end

  def test_a_slow_git_raises_timeout
    dir = fixture('clean')
    bin = fake_git(@root, 'exec sleep 30')
    repo = Slipway::Git::Repository.new(runner: Slipway::Git::Runner.new(timeout: 0.2))

    with_env('PATH' => "#{bin}:#{ENV.fetch('PATH')}") do
      error = assert_raises(Slipway::Git::Timeout) { repo.status(dir) }

      assert_equal "#{dir}: git did not finish within 0.2 seconds", error.message
    end
  end

  def test_a_missing_git_raises_not_installed
    dir = fixture('clean')
    repo = Slipway::Git::Repository.new(runner: Slipway::Git::Runner.new(binary: 'slipway-missing-git'))

    assert_raises(Slipway::Git::NotInstalled) { repo.status(dir) }
  end

  def test_dubious_ownership_is_reported_with_git_remedy_as_the_hint
    dir = fixture('clean')
    stderr = "fatal: detected dubious ownership in repository at '#{dir}'\n" \
             "To add an exception for this directory, call:\n"
    repo = Slipway::Git::Repository.new(runner: CannedRunner.new(128, stderr))

    error = assert_raises(Slipway::Git::UnsafeRepository) { repo.status(dir) }

    assert_equal "#{dir}: repository has dubious ownership", error.message
    assert_equal "Run 'git config --global --add safe.directory #{dir}' to trust it.", error.hint
  end

  def test_other_git_failures_keep_the_first_stderr_line
    dir = fixture('clean')
    repo = Slipway::Git::Repository.new(runner: CannedRunner.new(128, "fatal: bad object HEAD\nmore\n"))

    error = assert_raises(Slipway::Git::Error) { repo.last_commit(dir) }

    assert_equal "#{dir}: git exited with status 128: fatal: bad object HEAD", error.message
    assert_equal 1, error.exit_status
  end

  private

  def fixture(state) = build_repo(File.join(@root, state), state)

  def head_of(dir) = git!(dir, 'rev-parse', 'HEAD')[0, 7]

  def expected(dir, **fields) = Slipway::Git::Status.new(head: head_of(dir), **fields)
end
