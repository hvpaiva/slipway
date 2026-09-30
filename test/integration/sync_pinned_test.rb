# frozen_string_literal: true

require 'test_helper'

# sync on real repositories pinned by spec.revision.
class SyncPinnedIntegrationTest < Minitest::Test
  include IntegrationHelper

  PROTOCOLS = { 'SLIPWAY_PROTOCOLS' => 'ssh:https:file' }.freeze

  # The pin names a commit only the fetch brings, and origin holds one more past it.
  def test_a_pin_ahead_of_head_is_reached_and_then_held_without_following_the_upstream
    with_network_home do |env|
      dir = File.join(env['HOME'], 'dev', 'hldr')
      path = repo(env, 'hldr', 'stale')
      pin = head("#{dir}-other")
      git!("#{dir}-other", 'commit', '-q', '--allow-empty', '-m', 'past the pin')
      git!("#{dir}-other", 'push', '-q', 'origin', 'main')
      seed(env, manifest('Project', 'hldr', path:, revision: pin))

      assert_equal [0, "project/hldr fast-forwarded\n  main #{GetRegistry::HEAD}..#{pin[0, 7]} (to the pinned " \
                       "revision)\n", ''], slipway('sync', env:)
      assert_equal [pin, 'slipway sync: Fast-forward'], [head(dir), git!(dir, 'reflog', '-1', '--format=%gs').chomp]
      assert_equal [0, "project/hldr unchanged\n  held at #{pin[0, 7]} by spec.revision\n", ''], slipway('sync', env:)
      assert_equal pin, head(dir)
    end
  end

  # git peels a pin that names an annotated tag to the commit it tags.
  def test_a_pin_naming_an_annotated_tag_is_reached_and_then_held_and_diff_finds_no_drift
    with_network_home do |env|
      dir = File.join(env['HOME'], 'dev', 'hldr')
      path = repo(env, 'hldr', 'stale')
      git!(dir, 'fetch', '-q')
      git!(dir, 'tag', '-a', '-m', 'v1', 'v1', 'origin/main')
      pin, tagged = %w[v1 v1^{commit}].map { git!(dir, 'rev-parse', it).chomp }
      seed(env, manifest('Project', 'hldr', path:, revision: pin))

      assert_equal [0, "project/hldr fast-forwarded\n  main #{GetRegistry::HEAD}..#{tagged[0, 7]} (to the pinned " \
                       "revision)\n", ''], slipway('sync', env:)
      assert_equal [0, "project/hldr unchanged\n  held at #{pin[0, 7]} by spec.revision\n", ''], slipway('sync', env:)
      assert_equal [[0, '', ''], tagged], [slipway('diff', env:), head(dir)]
    end
  end

  # The pin is a commit a pushed side branch holds on top of main, which origin/main never had.
  def test_a_pin_its_upstream_lacks_is_skipped_and_the_branch_stays
    with_network_home do |env|
      dir = File.join(env['HOME'], 'dev', 'hldr')
      path = repo(env, 'hldr', 'stale')
      pin = push_side_branch("#{dir}-other")
      seed(env, manifest('Project', 'hldr', path:, revision: pin))
      before = branch(dir)

      assert_equal [0, <<~TEXT, ''], slipway('sync', env:)
        project/hldr skipped (OffUpstream)
          spec.revision #{pin[0, 7]} is not on origin/main; sync moves a branch only along its upstream
          git -C ~/dev/hldr log --oneline @{upstream}..#{pin[0, 7]}
      TEXT
      assert_equal before, branch(dir)
    end
  end

  def test_a_head_past_the_pin_or_a_pin_the_repository_lacks_is_skipped
    with_network_home do |env|
      dir = File.join(env['HOME'], 'dev', 'ahead')
      path = repo(env, 'ahead', 'ahead')
      before = head(dir)
      base = git!(dir, 'rev-parse', 'HEAD~1').chomp
      seed(env, manifest('Project', 'ahead', path:, revision: base),
           manifest('Project', 'lost', path: repo(env, 'lost', 'stale'), revision: 'f' * 40))

      assert_equal [0, <<~TEXT, "2 projects: 2 skipped\n"], slipway('sync', env:)
        project/ahead skipped (PastRevision)
          main is past the pinned revision; sync never moves a branch back
          git -C ~/dev/ahead log --oneline #{base[0, 7]}..HEAD
        project/lost skipped (RevisionNotFound)
          spec.revision fffffff is not in this repository; fetch it or unpin
      TEXT
      assert_equal before, head(dir)
    end
  end

  private

  def with_network_home
    with_home { |env| yield env.merge(PROTOCOLS) }
  end

  def head(dir) = git!(dir, 'rev-parse', 'HEAD').chomp

  def branch(dir) = [git!(dir, 'for-each-ref', 'refs/heads'), head(dir), File.binread(File.join(dir, '.git', 'index'))]

  def push_side_branch(clone)
    git!(clone, 'checkout', '-q', '-b', 'side')
    git!(clone, 'commit', '-q', '--allow-empty', '-m', 'side work')
    git!(clone, 'push', '-q', 'origin', 'side')
    head(clone)
  end
end
