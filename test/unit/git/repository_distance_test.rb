# frozen_string_literal: true

require 'open3'
require 'test_helper'
require 'tmpdir'

# Where HEAD stands against a pinned revision, read from real repositories.
class GitRepositoryDistanceTest < Minitest::Test
  include GitFixtures

  # Keeps a check of the object store from fetching what it looks for.
  OFFLINE = GitEnv::ENVIRONMENT.merge(Slipway::Git::Repository::OFFLINE_READ).freeze

  def setup
    @root = Dir.mktmpdir('slipway-distance-')
    @saved = replace_env(hermetic_env(@root))
    @repo = Slipway::Git::Repository.new
  end

  def teardown
    restore_env(@saved)
    FileUtils.remove_entry(@root)
  end

  def test_a_commit_ahead_of_head_is_behind_it_and_head_itself_is_nowhere
    dir = build_repo(File.join(@root, 'stale'), 'stale')
    git!(dir, 'fetch', '-q')
    upstream = git!(dir, 'rev-parse', 'origin/main').chomp

    assert_equal Slipway::Git::Distance.new(ahead: 0, behind: 1), @repo.distance(dir, upstream)
    assert_equal Slipway::Git::Distance.new(ahead: 0, behind: 0), @repo.distance(dir, rev(dir, 'HEAD'))
  end

  # A pushed side branch holds a commit that descends from HEAD but that main upstream never had.
  def test_a_tracking_branch_behind_the_revision_learns_how_many_of_its_commits_the_upstream_lacks
    dir = build_repo(File.join(@root, 'stale'), 'stale')
    upstream = rev("#{dir}-other", 'HEAD')
    side = push_side_branch("#{dir}-other")
    git!(dir, 'fetch', '-q')

    assert_equal distance(0, 1, 0), @repo.distance(dir, upstream, tracking: true)
    assert_equal distance(0, 2, 1), @repo.distance(dir, side, tracking: true)
    assert_equal distance(0, 2, nil), @repo.distance(dir, side)
    assert_equal distance(0, 0, nil), @repo.distance(dir, rev(dir, 'HEAD'), tracking: true)
  end

  def test_head_past_the_revision_or_beside_it_is_ahead
    dir = build_repo(File.join(@root, 'diverged'), 'diverged')
    base = rev(dir, 'HEAD~1')
    upstream = rev(dir, 'origin/main')

    assert_equal Slipway::Git::Distance.new(ahead: 1, behind: 0), @repo.distance(dir, base)
    assert_equal Slipway::Git::Distance.new(ahead: 1, behind: 1), @repo.distance(dir, upstream)
  end

  def test_an_object_name_that_is_no_commit_here_has_no_distance
    dir = build_repo(File.join(@root, 'clean'), 'clean')

    assert_nil @repo.distance(dir, 'f' * 40)
    assert_nil @repo.distance(dir, rev(dir, 'HEAD:README.md'))
  end

  def test_only_a_full_object_name_is_asked
    dir = build_repo(File.join(@root, 'clean'), 'clean')

    error = assert_raises(ArgumentError) { @repo.distance(dir, rev(dir, 'HEAD')[0, 7]) }

    assert_match(/full object name/, error.message)
  end

  # A partial clone would fetch the missing object from its remote otherwise.
  def test_the_read_tells_git_not_to_fetch_a_missing_object
    dir = build_repo(File.join(@root, 'clean'), 'clean')
    runner = RecordingEnvRunner.new
    repo = Slipway::Git::Repository.new(runner:)

    repo.distance(dir, 'f' * 40)

    assert_equal [{ 'GIT_NO_LAZY_FETCH' => '1', 'GIT_ALLOW_PROTOCOL' => '' }], runner.envs
    assert_includes runner.argvs.first, '--missing=allow-any'
  end

  # The pin was committed on the origin after the clone, so only a lazy fetch could bring it.
  def test_a_partial_clone_keeps_a_pin_it_lacks_on_its_remote_without_the_offline_environment
    origin = build_repo(File.join(@root, 'origin'), 'clean')
    git!(origin, 'config', 'uploadpack.allowFilter', 'true')
    dir = File.join(@root, 'partial')
    git!(@root, 'clone', '-q', '--filter=blob:none', "file://#{origin}", dir)
    commit(origin, 'late.txt', "late\n", 'after the clone')
    pin = rev(origin, 'HEAD')

    assert_nil Slipway::Git::Repository.new(runner: UnguardedRunner.new).distance(dir, pin)
    refute_predicate Open3.capture3(OFFLINE, 'git', '-C', dir, 'cat-file', '-e', pin).last, :success?
  end

  # Keeps the arguments and the extra environment of every git command it started.
  class RecordingEnvRunner < Slipway::Git::Runner
    attr_reader :argvs, :envs

    def initialize(...)
      super
      @argvs = []
      @envs = []
    end

    def run(path, *args, env: {}, **)
      @argvs << args
      @envs << env
      super
    end
  end

  # Drops the environment that keeps a read offline, as a git that honored none of it would.
  class UnguardedRunner < Slipway::Git::Runner
    def run(path, *, env: {}, **) = super(path, *, env: env.except(*OFFLINE.keys), **)
  end

  private

  def rev(dir, name) = git!(dir, 'rev-parse', name).chomp

  def distance(ahead, behind, off_upstream) = Slipway::Git::Distance.new(ahead:, behind:, off_upstream:)

  def push_side_branch(clone)
    git!(clone, 'checkout', '-q', '-b', 'side')
    commit(clone, 'side.txt', "side\n", 'side work')
    git!(clone, 'push', '-q', 'origin', 'side')
    rev(clone, 'HEAD')
  end
end
