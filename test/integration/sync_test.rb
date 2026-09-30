# frozen_string_literal: true

require 'test_helper'

class SyncIntegrationTest < Minitest::Test
  include IntegrationHelper

  # The fixtures' origins are local paths, which git reaches over the file transport.
  PROTOCOLS = { 'SLIPWAY_PROTOCOLS' => 'ssh:https:file' }.freeze

  def test_a_stale_branch_is_fast_forwarded_once_and_git_names_slipway_in_its_reflog
    with_network_home do |env|
      dir = project(env, 'stale')
      old = head(dir)
      pushed = head("#{dir}-other")

      assert_equal [0, "project/stale fast-forwarded\n  main #{old[0, 7]}..#{pushed[0, 7]} (1 commit); undo with " \
                       "'slipway rollout undo project/stale'\n", ''], slipway('sync', env:)
      assert_equal [pushed, 'slipway sync: Fast-forward'], [head(dir), reflog(dir).first]
      assert_equal [0, "project/stale unchanged\n", ''], slipway('sync', env:)
      assert_equal 2, reflog(dir).size
    end
  end

  # The line is run later without -n, so a group typed on this one has to travel with it.
  def test_the_undo_command_keeps_a_group_typed_with_n
    with_network_home do |env|
      seed(env, manifest('Group', 'work'), manifest('Project', 'api', group: 'work', path: repo(env, 'api', 'stale')))

      assert_equal [0, <<~TEXT, ''], scrub(slipway('sync', 'api', '-n', 'work', env:))
        project/api fast-forwarded
          main <range> (1 commit); undo with 'slipway rollout undo project/api -n work'
      TEXT
    end
  end

  def test_local_changes_keep_the_branch_where_it_is_and_untracked_files_do_not
    with_network_home do |env|
      dirty, scratch = %w[dirty scratch].map { project(env, it) }
      File.write(File.join(dirty, 'README.md'), "hello\nchanged\n")
      File.write(File.join(scratch, 'notes.txt'), "mine\n")
      before = head(dirty)

      assert_equal [0, <<~TEXT, "2 projects: 1 fast-forwarded, 1 skipped\n"], scrub(slipway('sync', env:))
        project/dirty skipped (Dirty)
          1 unstaged; sync fast-forwards only a tree without staged or unstaged changes
          git -C ~/dev/dirty status
        project/scratch fast-forwarded
          main <range> (1 commit); undo with 'slipway rollout undo project/scratch'
      TEXT
      assert_equal [before, "mine\n"], [head(dirty), File.read(File.join(scratch, 'notes.txt'))]
    end
  end

  def test_git_refusing_to_overwrite_an_untracked_file_or_to_take_a_held_lock_is_relayed
    with_network_home do |env|
      overlap = project(env, 'overlap', 'stale_untracked_overlap')
      locked = project(env, 'locked', 'index_lock')
      before = [overlap, locked].map { head(it) }

      assert_equal [0, <<~TEXT, "2 projects: 2 skipped\n"], slipway('sync', env:)
        project/locked skipped (Busy)
          another git process holds index.lock, or one left it behind; sync never removes a lock
        project/overlap skipped (WouldOverwrite)
          the incoming commits would overwrite untracked files; move them and run sync again
          git -C ~/dev/overlap status
      TEXT
      assert_equal(before, [overlap, locked].map { head(it) })
      assert_equal "local b\n", File.read(File.join(overlap, 'b.txt'))
      assert_path_exists File.join(locked, '.git', 'index.lock')
    end
  end

  def test_a_branch_that_cannot_follow_its_upstream_is_skipped_and_nothing_moves
    with_network_home do |env|
      dirs = { 'diverged' => project(env, 'diverged', 'diverged'), 'gone' => project(env, 'gone', 'gone'),
               'loose' => project(env, 'loose', 'synced') }
      git!(dirs['loose'], 'checkout', '-q', '--detach')
      before = dirs.transform_values { branches(it) }

      status, out, = slipway('sync', env:)

      assert_equal [0, ['diverged skipped (Diverged)', 'gone skipped (Gone)', 'loose skipped (Detached)']],
                   [status, out.lines.grep(/\Aproject/).map { it.delete_prefix('project/').chomp }]
      assert_equal(before, dirs.transform_values { branches(it) })
    end
  end

  def test_a_fetch_only_project_is_fetched_and_its_branch_stays
    with_network_home do |env|
      dir = project(env, 'tool', syncPolicy: 'FetchOnly')
      before = head(dir)

      assert_equal [0, "project/tool fetched\n  origin/main #{before[0, 7]}..#{head("#{dir}-other")[0, 7]}\n  " \
                       "Behind: 1 commit behind origin/main; syncPolicy is FetchOnly\n", ''], slipway('sync', env:)
      assert_equal before, head(dir)
    end
  end

  def test_a_paused_project_and_a_dry_run_leave_every_repository_as_it_was
    with_network_home do |env|
      paused = project(env, 'dots', paused: true)
      stale = project(env, 'stale')
      before = [paused, stale].map { snapshot(it) }

      assert_equal [0, "project/dots paused (dry run)\nproject/stale unchanged (dry run)\n"],
                   slipway('sync', '--dry-run', env:).first(2)
      assert_equal [0, "project/dots paused\n"], slipway('sync', 'dots', env:).first(2)
      assert_equal(before, [paused, stale].map { snapshot(it) })
      [paused, stale].each { refute_path_exists File.join(it, '.git', 'FETCH_HEAD') }
    end
  end

  def test_a_post_merge_hook_runs_and_its_output_stays_out_of_the_result
    with_network_home do |env|
      dir = project(env, 'hooked')
      marker = File.join(env['HOME'], 'merged')
      hook = File.join(dir, '.git', 'hooks', 'post-merge')
      File.write(hook, "#!/bin/sh\necho hook noise\necho hook noise >&2\ntouch #{marker}\n")
      File.chmod(0o755, hook)

      status, out, err = slipway('sync', env:)

      assert_equal [0, ''], [status, err]
      assert_match(%r{\Aproject/hooked fast-forwarded\n  main \h{7}\.\.\h{7} \(1 commit\)}, out)
      refute_includes out, 'hook noise'
      assert_path_exists marker
    end
  end

  private

  def with_network_home
    with_home { |env| yield env.merge(PROTOCOLS) }
  end

  def project(env, name, state = 'stale', **spec)
    seed(env, manifest('Project', name, path: repo(env, name, state), **spec))
    File.join(env['HOME'], 'dev', name)
  end

  def head(dir) = git!(dir, 'rev-parse', 'HEAD').chomp

  def reflog(dir) = git!(dir, 'reflog', 'show', '--format=%gs', 'refs/heads/main').lines(chomp: true)

  # The fetch still moves remote-tracking refs, so only the branch, HEAD and the index count.
  def branches(dir) = [git!(dir, 'for-each-ref', 'refs/heads'), head(dir), index(dir)]

  def snapshot(dir) = [git!(dir, 'for-each-ref'), git!(dir, 'status', '--porcelain=v2', '--branch'), index(dir)]

  def index(dir) = File.binread(File.join(dir, '.git', 'index'))

  def scrub(result) = [result[0], result[1].gsub(/\h{7}\.\.\h{7}/, '<range>'), result[2]]
end
