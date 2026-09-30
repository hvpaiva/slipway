# frozen_string_literal: true

require 'test_helper'
require 'tmpdir'
require_relative '../../../rakelib/support/commits'

class BranchRangeTest < Minitest::Test
  include GitEnv

  def setup
    @dir = Dir.mktmpdir('slipway-range-')
    git!(@dir, 'init', '--quiet')
    git!(@dir, 'commit', '--quiet', '--allow-empty', '-m', 'chore: start')
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def branch_range = with_env(GitEnv::ENVIRONMENT) { Commits.branch_range(chdir: @dir) }

  def test_a_clone_without_origin_main_has_nothing_to_compare_with
    assert_equal [nil, 'no origin/main to compare HEAD with'], branch_range
  end

  def test_head_at_origin_main_has_nothing_to_lint
    git!(@dir, 'update-ref', 'refs/remotes/origin/main', 'HEAD')

    assert_equal [nil, 'HEAD has no commits that origin/main lacks'], branch_range
  end

  def test_commits_after_origin_main_are_the_range
    git!(@dir, 'update-ref', 'refs/remotes/origin/main', 'HEAD')
    git!(@dir, 'commit', '--quiet', '--allow-empty', '-m', 'feat: add x')

    assert_equal ['origin/main..HEAD', nil], branch_range
  end
end
