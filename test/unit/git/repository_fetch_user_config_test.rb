# frozen_string_literal: true

require 'test_helper'
require 'slipway/git'
require 'tmpdir'

# The fetch runs under the user's own git configuration, so a setting that changes which remotes
# a remote-less fetch reads must not change what it fetches.
class GitRepositoryFetchUserConfigTest < Minitest::Test
  include GitFixtures

  def setup
    @root = Dir.mktmpdir('slipway-fetch-config-')
    @saved = replace_env(hermetic_env(@root))
    @repo = Slipway::Git::Repository.new(protocols: %w[file])
  end

  def teardown
    restore_env(@saved)
    FileUtils.remove_entry(@root)
  end

  def test_fetch_all_with_a_second_remote_still_fetches_only_origin
    dir = build_repo(File.join(@root, 'stale'), 'stale')
    git!(dir, 'remote', 'add', 'upstream', "#{dir}-origin.git")
    git!(dir, 'config', 'fetch.all', 'true')

    result = @repo.fetch(dir, prune: false)

    assert_equal 1, @repo.status(dir).behind
    skip_unless_fetch_lists_refs

    assert_equal [['refs/remotes/origin/main', head(dir), head("#{dir}-other")]], result.updates
  end

  private

  def head(dir) = git!(dir, 'rev-parse', 'HEAD').chomp
end
