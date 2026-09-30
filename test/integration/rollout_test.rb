# frozen_string_literal: true

require 'test_helper'

# rollout on real repositories: slipway's own moves read back from the branch reflog and undone.
class RolloutIntegrationTest < Minitest::Test
  include IntegrationHelper

  PROTOCOLS = { 'SLIPWAY_PROTOCOLS' => 'ssh:https:file' }.freeze

  def test_undo_returns_to_the_old_commit_and_sync_then_holds_it
    with_network_home do |env|
      dir, old, new = after_sync(env)

      assert_equal([1, 2], history(env).map { it[0].to_i })
      assert_equal [0, <<~TEXT, ''], slipway('rollout', 'undo', 'stale', env:)
        project/stale rolled back
          main #{new[0, 7]}..#{old[0, 7]} (1 commit back to revision 1); held there by spec.revision
          'slipway rollout unpin project/stale' follows origin/main again
      TEXT
      assert_equal [old, old, 'slipway rollout undo: updating HEAD'], [head(dir), pin(env), reflog(dir).first]
      assert_equal [0, "project/stale unchanged\n  held at #{old[0, 7]} by spec.revision\n", ''], slipway('sync', env:)
      assert_equal old, head(dir)
    end
  end

  def test_undo_to_a_later_revision_moves_forward_and_unpin_lets_sync_follow_the_upstream
    with_network_home do |env|
      dir, _, new = after_sync(env)
      slipway!('rollout', 'undo', 'stale', env:)
      slipway!('rollout', 'undo', 'stale', '--to-revision=2', env:)

      assert_equal [new, new], [head(dir), pin(env)]
      assert_equal([['rollout undo to revision 1', 'false'], ['rollout undo to revision 2', 'true']],
                   history(env).last(2).map { it[3, 2] })
      assert_follows_after_unpin(env, dir, new)
    end
  end

  def test_a_dry_run_moves_nothing_and_writes_nothing
    with_network_home do |env|
      dir, old, new = after_sync(env)
      manifest = File.read(manifest_file(env))

      assert_equal "project/stale rolled back (dry run)\n  main #{new[0, 7]}..#{old[0, 7]} (1 commit back to " \
                   "revision 1); held there by spec.revision\n", slipway('rollout', 'undo', 'stale', '--dry-run=client',
                                                                         env:)[1].lines.first(2).join
      assert_equal [new, manifest], [head(dir), File.read(manifest_file(env))]
    end
  end

  def test_a_commit_made_after_the_sync_is_never_dropped
    with_network_home do |env|
      dir, = after_sync(env)
      commit(dir, 'mine.txt', "mine\n", 'local work')
      before = branch(dir)

      assert_equal [1, <<~TEXT, ''], slipway('rollout', 'undo', 'stale', env:)
        project/stale skipped (LocalCommits)
          main has commits that are not on origin/main; undo would drop them
          git -C ~/dev/stale log --oneline @{upstream}..HEAD
      TEXT
      assert_equal [before, nil], [branch(dir), pin(env)]
    end
  end

  def test_a_modified_file_the_move_would_rewrite_keeps_the_branch_and_the_file
    with_network_home do |env|
      dir, = after_sync(env)
      File.write(File.join(dir, 'b.txt'), "edited\n")
      before = head(dir)

      assert_equal [1, <<~TEXT, ''], slipway('rollout', 'undo', 'stale', env:)
        project/stale skipped (WouldLoseChanges)
          the move would overwrite local changes; commit or move them and run undo again
          git -C ~/dev/stale status
      TEXT
      assert_equal [before, "edited\n", nil], [head(dir), File.read(File.join(dir, 'b.txt')), pin(env)]
    end
  end

  def test_a_detached_head_is_refused
    with_network_home do |env|
      dir, = after_sync(env)
      git!(dir, 'checkout', '-q', '--detach')
      before = head(dir)

      assert_equal 'project/stale skipped (Detached)', slipway('rollout', 'undo', 'stale', env:)[1].lines.first.chomp
      assert_equal [before, nil], [head(dir), pin(env)]
    end
  end

  def test_history_is_empty_when_git_logs_no_ref_updates
    with_network_home do |env|
      dir = File.join(env['HOME'], 'dev', 'quiet')
      seed(env, manifest('Project', 'quiet', path: repo(env, 'quiet', 'stale')))
      FileUtils.rm_rf(File.join(dir, '.git', 'logs'))
      git!(dir, 'config', 'core.logAllRefUpdates', 'false')
      slipway!('sync', env:)

      assert_equal [0, '', "No rollout history found for project/quiet.\n"],
                   slipway('rollout', 'history', 'quiet', env:)
    end
  end

  def test_pause_and_resume_change_only_spec_paused
    with_network_home do |env|
      seed(env, manifest('Project', 'dots', path: repo(env, 'dots', 'stale'), branch: 'main'))
      before = File.read(manifest_file(env, 'dots'))

      assert_equal [0, "project/dots paused\n", ''], slipway('rollout', 'pause', 'dots', env:)
      assert_equal before.sub("branch: main\n", "branch: main\n  paused: true\n"),
                   File.read(manifest_file(env, 'dots'))
      assert_equal "project/dots paused\n", slipway('sync', env:)[1]
      assert_equal [0, "project/dots resumed\n", ''], slipway('rollout', 'resume', 'dots', env:)
      assert_equal before, File.read(manifest_file(env, 'dots'))
    end
  end

  private

  # Held at +pinned+ while origin moves on, then fast-forwarded to origin once unpinned.
  def assert_follows_after_unpin(env, dir, pinned)
    latest = push_upstream("#{dir}-other")

    assert_equal "project/stale unchanged\n  held at #{pinned[0, 7]} by spec.revision\n", slipway('sync', env:)[1]
    assert_equal [0, "project/stale unpinned\n", ''], slipway('rollout', 'unpin', 'stale', env:)
    assert_equal 'project/stale fast-forwarded', slipway('sync', env:)[1].lines.first.chomp
    assert_equal latest, head(dir)
  end

  def with_network_home
    with_home { |env| yield env.merge(PROTOCOLS) }
  end

  # The stale fixture after one sync: its directory, the commit before and the one after it.
  def after_sync(env)
    dir = File.join(env['HOME'], 'dev', 'stale')
    seed(env, manifest('Project', 'stale', path: repo(env, 'stale', 'stale')))
    old = head(dir)
    slipway!('sync', env:)
    [dir, old, head(dir)]
  end

  def push_upstream(clone)
    commit(clone, 'c.txt', "c\n", 'more remote work')
    git!(clone, 'push', '-q', 'origin', 'main')
    head(clone)
  end

  def history(env) = table(slipway!('rollout', 'history', 'stale', env:)).drop(1)

  def manifest_file(env, name = 'stale') = File.join(data_home(env), 'projects', 'default', "#{name}.yaml")

  def pin(env) = Psych.safe_load_file(manifest_file(env)).dig('spec', 'revision')

  def head(dir) = git!(dir, 'rev-parse', 'HEAD').chomp

  def reflog(dir) = git!(dir, 'reflog', 'show', '--format=%gs', 'refs/heads/main').lines(chomp: true)

  def branch(dir) = [git!(dir, 'for-each-ref', 'refs/heads'), head(dir), File.binread(File.join(dir, '.git', 'index'))]
end
