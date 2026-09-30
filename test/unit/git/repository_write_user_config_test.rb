# frozen_string_literal: true

require 'test_helper'
require 'slipway/git'
require 'tmpdir'

# The fast-forward runs under the user's own git configuration, so a setting that asks git to
# rebase, stash or always create a merge commit must not change what it does.
class GitRepositoryWriteUserConfigTest < Minitest::Test
  include GitFixtures

  CONFIG = <<~INI
    [pull]
    \trebase = true
    [rebase]
    \tautoStash = true
    [merge]
    \tautoStash = true
    \tff = false
    [branch "main"]
    \tmergeOptions = --no-ff
  INI

  def setup
    @root = Dir.mktmpdir('slipway-write-config-')
    global = File.join(@root, 'gitconfig')
    File.write(global, CONFIG)
    @saved = replace_env(hermetic_env(@root).merge('GIT_CONFIG_GLOBAL' => global))
  end

  def teardown
    restore_env(@saved)
    FileUtils.remove_entry(@root)
  end

  def test_a_configuration_that_asks_for_a_rebase_a_stash_or_a_merge_commit_still_fast_forwards
    dir = build_repo(File.join(@root, 'stale'), 'stale')
    git!(dir, 'fetch', '-q')
    runner = RecordingRunner.new

    Slipway::Git::Repository.new(runner:).fast_forward(dir)

    assert_empty runner.commands.flatten & %w[pull rebase stash --rebase --autostash]
    assert_includes runner.commands.last, '--no-autostash'
    assert_equal git!(dir, 'rev-parse', 'origin/main'), git!(dir, 'rev-parse', 'HEAD')
    assert_equal 2, git!(dir, 'rev-list', '--parents', '-1', 'HEAD').split.size
    assert_empty git!(dir, 'stash', 'list')
  end
end
