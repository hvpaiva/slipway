# frozen_string_literal: true

require 'test_helper'

class StatesIntegrationTest < Minitest::Test
  include IntegrationHelper

  # Every fixture state plus a plain directory and a path that does not exist, with the STATUS
  # word and the BRANCH cell each one shows.
  EXPECTED = {
    'ahead' => %w[main Ahead], 'behind' => %w[main Behind], 'clean' => %w[main Clean],
    'conflicted' => %w[main Conflicted], 'detached' => %w[(detached) Detached], 'diverged' => %w[main Diverged],
    'gone' => %w[feature Gone], 'missing' => %w[<none> Missing], 'plain' => %w[<none> NotARepo],
    'staged' => %w[main Dirty], 'stash' => %w[main Clean], 'unborn' => %w[main Unborn],
    'unstaged' => %w[main Dirty], 'untracked' => %w[main Dirty]
  }.freeze
  FIXTURE_OF = { 'missing' => nil, 'plain' => 'plain_dir' }.freeze

  def everything(env)
    seed(env, *EXPECTED.keys.map { manifest('Project', it, path: repo(env, it, FIXTURE_OF.fetch(it, it))) })
  end

  def test_the_status_column_names_every_state
    with_home do |env|
      everything(env)
      status, out, err = slipway('get', 'projects', env:)

      assert_equal [0, ''], [status, err]
      assert_table [%w[NAME BRANCH STATUS AGE], *EXPECTED.map { |name, (branch, state)| [name, branch, state, :age] }],
                   out
    end
  end

  def test_the_stash_count_is_visible_in_describe_but_does_not_make_a_repository_dirty
    with_home do |env|
      seed(env, manifest('Project', 'stash', path: repo(env, 'stash', 'stash')))
      _, out, = slipway('describe', 'project', 'stash', env:)

      assert_includes out, "Status:       Clean\n"
      assert_includes out, "  Stashes:     2\n"
    end
  end

  def test_diverged_counts_both_directions
    with_home do |env|
      seed(env, manifest('Project', 'diverged', path: repo(env, 'diverged', 'diverged')))
      _, out, = slipway('describe', 'project', 'diverged', env:)

      assert_includes out, "  Upstream:    origin/main\n  Ahead:       1\n  Behind:      1\n"
    end
  end

  def test_without_git_on_path_repositories_are_unknown_and_one_warning_is_printed
    with_home do |env|
      seed(env, manifest('Project', 'clean', path: repo(env, 'clean')),
           manifest('Project', 'dirty', path: repo(env, 'dirty', 'untracked')),
           manifest('Project', 'missing', path: repo(env, 'missing', nil)))
      status, out, err = slipway('get', 'projects', env: env.merge('PATH' => '/nonexistent'))

      assert_equal 0, status
      assert_equal "warning: git executable \"git\" not found on PATH\n", err
      assert_table [%w[NAME BRANCH STATUS AGE], ['clean', '<none>', 'Unknown', :age],
                    ['dirty', '<none>', 'Unknown', :age], ['missing', '<none>', 'Missing', :age]], out
      assert_equal [0, "project/clean\nproject/dirty\nproject/missing\n", ''],
                   slipway('get', 'projects', '-o', 'name', env: env.merge('PATH' => '/nonexistent'))
    end
  end

  def test_describe_names_the_reason_for_an_unknown_state
    with_home do |env|
      seed(env, manifest('Project', 'clean', path: repo(env, 'clean')))
      status, out, err = slipway('describe', 'project', 'clean', env: env.merge('PATH' => '/nonexistent'))

      assert_equal 0, status
      assert_equal "warning: git executable \"git\" not found on PATH\n", err
      assert_includes out, "Status:       Unknown\nRepository:   git executable \"git\" not found on PATH\n" \
                           "Last Commit:  <none>\n"
    end
  end
end
