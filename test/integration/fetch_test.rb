# frozen_string_literal: true

require 'json'
require 'test_helper'

class FetchIntegrationTest < Minitest::Test
  include IntegrationHelper

  # The fixtures' origins are local paths, which git reaches over the file transport.
  PROTOCOLS = { 'SLIPWAY_PROTOCOLS' => 'ssh:https:file' }.freeze
  TIMESTAMP = /\A\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ\z/
  SKIPPED = <<~TEXT
    project/clean skipped (NoRemote)
      no upstream, no origin and no single remote to fetch from
    project/missing skipped (Missing)
      ~/dev/missing: no such directory
    project/plain skipped (NotARepo)
      ~/dev/plain: not a git repository
  TEXT

  def test_a_stale_project_is_fetched_and_a_synced_one_is_unchanged
    skip_unless_fetch_lists_refs
    with_home do |env|
      env = env.merge(PROTOCOLS)
      seed(env, manifest('Project', 'stale', path: repo(env, 'stale', 'stale')),
           manifest('Project', 'synced', path: repo(env, 'synced', 'synced')))
      pushed = git!(File.join(env['HOME'], 'dev', 'stale-other'), 'rev-parse', 'HEAD')[0, 7]

      assert_equal [0, "project/stale fetched\n  origin/main #{GetRegistry::HEAD}..#{pushed}\n" \
                       "project/synced unchanged\n", "2 projects: 1 fetched, 1 unchanged\n"], slipway('fetch', env:)
      assert_table [%w[NAME BRANCH STATUS FETCHED AGE], ['stale', 'main', 'Behind', :age, :age],
                    ['synced', 'main', 'Clean', :age, :age]], slipway!('get', 'projects', env:)
      assert_equal [0, "project/stale unchanged\nproject/synced unchanged\n", "2 projects: 2 unchanged\n"],
                   slipway('fetch', env:)
    end
  end

  def test_the_time_of_the_fetch_reaches_json_and_describe
    with_home do |env|
      env = env.merge(PROTOCOLS)
      seed(env, manifest('Project', 'synced', path: repo(env, 'synced', 'synced')))
      before = JSON.parse(slipway!('get', 'project', 'synced', '-o', 'json', env:)).fetch('status')
      slipway!('fetch', env:)
      after = JSON.parse(slipway!('get', 'project', 'synced', '-o', 'json', env:)).fetch('status')

      refute_includes before.keys, 'lastFetch'
      assert_match TIMESTAMP, after.fetch('lastFetch')
      assert_includes slipway!('describe', 'project', 'synced', env:), "  Last Fetch:  #{after.fetch('lastFetch')}\n"
    end
  end

  def test_a_transport_the_protocols_setting_leaves_out_fails_the_project
    with_home do |env|
      seed(env, manifest('Project', 'stale', path: repo(env, 'stale', 'stale')))
      expected = "project/stale failed (ProtocolNotAllowed)\n  transport 'file' not allowed\n  " \
                 "Add file to \"protocols\" in #{config_file(env)} to allow it.\n"

      assert_equal [1, expected, ''], slipway('fetch', env:)
      assert_equal %w[stale main Clean <never>], table(slipway!('get', 'projects', env:)).last.first(4)
    end
  end

  def test_projects_without_a_repository_or_a_remote_are_skipped_before_any_fetch
    with_home do |env|
      env = env.merge(PROTOCOLS)
      seed(env, manifest('Project', 'clean', path: repo(env, 'clean')),
           manifest('Project', 'missing', path: repo(env, 'missing', nil)),
           manifest('Project', 'plain', path: repo(env, 'plain', 'plain_dir')))

      assert_equal [0, SKIPPED, "3 projects: 3 skipped\n"], slipway('fetch', env:)
      refute_path_exists File.join(env['HOME'], 'dev', 'clean', '.git', 'FETCH_HEAD')
    end
  end

  # Without an upstream or an origin, git fetches the only remote and nothing when there are two.
  def test_a_sole_remote_not_named_origin_is_fetched_without_an_upstream
    skip_unless_fetch_lists_refs
    with_home do |env|
      env = env.merge(PROTOCOLS)
      fork, twins = %w[fork twins].map { File.join(env['HOME'], 'dev', it) }
      seed(env, *%w[fork twins].map { manifest('Project', it, path: repo(env, it, 'stale')) })
      [fork, twins].each { git!(it, 'remote', 'rename', 'origin', 'github') }
      git!(fork, 'checkout', '-q', '-b', 'feat')
      git!(twins, 'remote', 'add', 'gitlab', "#{twins}-origin.git")
      git!(twins, 'checkout', '-q', '--detach')
      pushed = git!("#{fork}-other", 'rev-parse', 'HEAD')[0, 7]
      expected = "project/fork fetched\n  github/main #{GetRegistry::HEAD}..#{pushed}\n" \
                 "project/twins skipped (NoRemote)\n  no upstream, no origin and no single remote to fetch from\n"

      assert_equal [0, expected, "2 projects: 1 fetched, 1 skipped\n"], slipway('fetch', env:)
      refute_path_exists File.join(twins, '.git', 'FETCH_HEAD')
    end
  end

  def test_a_dry_run_contacts_no_remote
    with_home do |env|
      env = env.merge(PROTOCOLS)
      seed(env, manifest('Project', 'stale', path: repo(env, 'stale', 'stale')))

      assert_equal [0, "project/stale fetched (dry run)\n", ''], slipway('fetch', '--dry-run=client', env:)
      refute_path_exists File.join(env['HOME'], 'dev', 'stale', '.git', 'FETCH_HEAD')
      assert_equal %w[stale main Clean <never>], table(slipway!('get', 'projects', env:)).last.first(4)
    end
  end

  def test_prune_removes_the_remote_tracking_ref_of_a_deleted_branch
    skip_unless_fetch_lists_refs
    with_home do |env|
      env = env.merge(PROTOCOLS)
      seed(env, manifest('Project', 'stale', path: repo(env, 'stale', 'stale')))
      dir = File.join(env['HOME'], 'dev', 'stale')
      git!("#{dir}-other", 'push', '-q', 'origin', 'HEAD:refs/heads/feature')
      slipway!('fetch', env:)
      git!("#{dir}-other", 'push', '-q', 'origin', '--delete', 'feature')
      feature = git!(dir, 'rev-parse', 'origin/feature')[0, 7]

      assert_equal "project/stale unchanged\n", slipway!('fetch', env:)
      assert_equal "project/stale fetched\n  origin/feature deleted (was #{feature})\n",
                   slipway!('fetch', '--prune', env:)
    end
  end

  # A linked worktree writes into the refs of its repository, where two fetches at once would
  # race on the ref locks and one of them would fail.
  def test_a_repository_and_its_linked_worktree_both_fetch
    skip_unless_fetch_lists_refs
    with_home do |env|
      env = env.merge(PROTOCOLS)
      dir = File.join(env['HOME'], 'dev', 'app')
      seed(env, manifest('Project', 'app', path: repo(env, 'app', 'stale')))
      git!(dir, 'worktree', 'add', '-q', "#{dir}-wt")
      seed(env, manifest('Project', 'app-wt', path: '~/dev/app-wt'))
      status, out, err = slipway('fetch', env:)

      assert_equal [0, %w[fetched unchanged], "2 projects: 1 fetched, 1 unchanged\n"],
                   [status, out.lines.grep(/\Aproject/).map { it.split[1] }.sort, err]
      assert_table [%w[NAME BRANCH STATUS FETCHED AGE], ['app', 'main', 'Behind', :age, :age],
                    ['app-wt', 'app-wt', 'Clean', :age, :age]], slipway!('get', 'projects', env:)
    end
  end
end
