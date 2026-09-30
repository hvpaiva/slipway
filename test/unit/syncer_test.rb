# frozen_string_literal: true

require 'test_helper'

# How sync runs: failures kept to their project, one write at a time, a dry run that only reads,
# and git's refusals and races relayed as they come.
class SyncerTest < Minitest::Test
  include CommandsHelper

  NEW = 'e4f5a6b7c8d9e0f1a2b3c4d5e6f7a8b9c0d1e2f3'
  BEHIND = CLEAN.with(behind: 1)
  MOVE = Slipway::Git::FastForward.new(from: SHA, to: NEW, count: 1)
  READS = %i[status last_commit remote_url fetched_at in_progress distance local_upstream? default_remote?
             common_dir].freeze

  RELAYED = <<~TEXT
    project/kept skipped (WouldLoseChanges)
      the incoming commits would overwrite local changes; commit or move them and run sync again
      git -C ~/dev/kept status
    project/moot skipped (NotFastForward)
      the branch cannot be fast-forwarded; sync never merges or rebases
      git -C ~/dev/moot status
    project/raced skipped (Dirty)
      1 staged, 0 unstaged
      git -C ~/dev/raced status
    project/still unchanged
  TEXT

  # Records the most fast-forwards that ever ran at once.
  class GaugedGit < Slipway::Git::Fake
    attr_reader :widest

    def initialize
      super
      @running = 0
      @widest = 0
      @gauge = Mutex.new
    end

    def fast_forward(...)
      @gauge.synchronize { @widest = [@widest, @running += 1].max }
      sleep 0.01
      super
    ensure
      @gauge.synchronize { @running -= 1 }
    end
  end

  # Two projects on one repository, as a linked worktree and its main one, that records whether a
  # fetch and a fast-forward ever ran at once. The worktree reads its status late, so its fetch
  # starts while the main one moves.
  class SharedGit < Slipway::Git::Fake
    attr_reader :overlapped

    def initialize
      super
      @busy = Hash.new(0)
      @gauge = Mutex.new
      @overlapped = false
    end

    def common_dir(_path) = 'shared'

    def status(path)
      sleep 0.05 if path.end_with?('-wt')
      super
    end

    def fetch(path, prune:) = gauged(:fetch) { super }

    def fast_forward(...)
      gauged(:fast_forward) do
        sleep 0.2
        super
      end
    end

    private

    def gauged(kind)
      @gauge.synchronize do
        @busy[kind] += 1
        @overlapped ||= @busy[:fetch].positive? && @busy[:fast_forward].positive?
      end
      yield
    ensure
      @gauge.synchronize { @busy[kind] -= 1 }
    end
  end

  # The repository stops being one right after its fetch, as when it is deleted meanwhile.
  class VanishingGit < Slipway::Git::Fake
    def fetch(path, prune:)
      super.tap { self.fail(path, Slipway::Git::NotARepository) }
    end
  end

  def test_a_failure_in_one_project_leaves_the_others_alone
    with_runtime do |runtime, home|
      register(runtime, 'api', fetch: Slipway::Git::Timeout.new("#{home}/dev/api", seconds: 60))
      register(runtime, 'hldr', status: BEHIND, fast_forward: MOVE)
      register(runtime, 'odd', status: BEHIND, fast_forward: Slipway::Git::Error.new("#{home}/dev/odd", 'exploded'))
      register(runtime, 'same')
      expected = <<~TEXT
        project/api failed (Timeout)
          git did not finish within 60 seconds
        project/hldr fast-forwarded
          main a1b2c3d..e4f5a6b (1 commit); undo with 'slipway rollout undo project/hldr'
        project/odd failed (Unknown)
          exploded
        project/same unchanged
      TEXT

      assert_equal [1, expected, "4 projects: 1 fast-forwarded, 1 unchanged, 2 failed\n"], run_sync(runtime:)
    end
  end

  def test_a_move_stopped_at_the_deadline_fails_and_points_at_the_files_it_left
    with_runtime do |runtime, home|
      stopped = Slipway::Git::WriteTimeout.new("#{home}/dev/hldr", seconds: 60)
      register(runtime, 'hldr', status: BEHIND, fast_forward: stopped)
      expected = <<~TEXT
        project/hldr failed (Timeout)
          git did not finish within 60 seconds; the files it had written stay in the working tree
          #{stopped.hint}
      TEXT

      assert_equal [1, expected], run_sync(runtime:).first(2)
    end
  end

  def test_fast_forwards_run_one_at_a_time
    with_sandbox do |env|
      runtime = sandbox_runtime(env.merge('SLIPWAY_PARALLEL' => '4'), git: GaugedGit.new)
      names = %w[a b c d e f]
      names.each { register(runtime, it, status: BEHIND, fast_forward: MOVE) }

      status, out, = run_sync(runtime:)

      assert_equal [0, ['fast-forwarded'] * names.size, 1],
                   [status, out.lines.grep(/\Aproject/).map { it.split[1] }, runtime.git.widest]
    end
  end

  def test_a_dry_run_only_reads
    with_runtime do |runtime|
      register(runtime, 'hldr', status: BEHIND, fast_forward: MOVE)
      register(runtime, 'dirty', status: BEHIND.with(unstaged: 1))
      register(runtime, 'pinned', distance: Slipway::Git::Distance.new(ahead: 0, behind: 1, off_upstream: 0),
                                  spec: { revision: NEW })
      register(runtime, 'tool', status: BEHIND, spec: { sync_policy: 'FetchOnly' })

      status, out, = run_sync('--dry-run', runtime:)

      assert_equal 0, status
      assert_equal(%w[skipped fast-forwarded fast-forwarded fetched], out.lines.grep(/\Aproject/).map { it.split[1] })
      assert_empty(runtime.git.calls.map(&:first).uniq - READS)
    end
  end

  # Both write the refs of the one repository, and git would fail one of them.
  def test_a_move_waits_for_a_fetch_of_the_same_repository
    with_sandbox do |env|
      runtime = sandbox_runtime(env.merge('SLIPWAY_PARALLEL' => '2'), git: SharedGit.new)
      register(runtime, 'app', status: BEHIND, fast_forward: MOVE)
      register(runtime, 'app-wt')

      status, out, = run_sync(runtime:)

      assert_equal [0, %w[fast-forwarded unchanged]], [status, out.lines.grep(/\Aproject/).map { it.split[1] }]
      refute runtime.git.overlapped
    end
  end

  # The line is copied and run without this invocation's -n, so it resolves the name in the
  # configured group.
  def test_the_undo_command_names_a_group_given_with_n
    with_sandbox do |env|
      runtime = sandbox_runtime(env, flags: { group: 'work' })
      register_group(runtime, 'work')
      register(runtime, 'api', group: 'work', status: BEHIND, fast_forward: MOVE)

      assert_includes run_sync('api', '-n', 'work', runtime:)[1], "undo with 'slipway rollout undo project/api -n work'"
    end
  end

  def test_the_undo_command_names_the_group_when_it_is_not_the_one_in_effect
    with_runtime do |runtime|
      register_group(runtime, 'work')
      register(runtime, 'api', group: 'work', status: BEHIND, fast_forward: MOVE)
      register(runtime, 'hldr', status: BEHIND, fast_forward: MOVE)

      undo = run_sync('-A', runtime:)[1].scan(/undo with '(.*)'$/).flatten

      assert_equal ['slipway rollout undo project/hldr', 'slipway rollout undo project/api -n work'], undo.sort.reverse
    end
  end

  def test_what_the_fast_forward_finds_right_before_it_moves_is_relayed
    with_runtime do |runtime, home|
      raced = Slipway::Git::Blocked.new("#{home}/dev/raced", 'Dirty', '1 staged, 0 unstaged')
      register(runtime, 'raced', status: BEHIND, fast_forward: raced)
      register(runtime, 'kept', status: BEHIND, fast_forward: Slipway::Git::WouldLoseChanges)
      register(runtime, 'moot', status: BEHIND, fast_forward: Slipway::Git::NotFastForward)
      register(runtime, 'still', status: BEHIND)

      assert_equal [0, RELAYED], run_sync('kept', 'moot', 'raced', 'still', runtime:).first(2)
    end
  end

  def test_a_repository_that_git_cannot_read_after_its_fetch_is_skipped
    with_sandbox do |env|
      runtime = sandbox_runtime(env, git: VanishingGit.new)
      register(runtime, 'hldr', status: BEHIND, fast_forward: MOVE)

      assert_equal [0, "project/hldr skipped (NotARepo)\n  ~/dev/hldr holds files but no repository; sync clones " \
                       "only into an absent directory\n", ''], run_sync(runtime:)
    end
  end

  private

  def run_sync(*, runtime:) = run_commands('sync', *, runtime:, commands: [Slipway::Commands::Sync])
end
