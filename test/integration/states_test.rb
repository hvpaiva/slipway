# frozen_string_literal: true

require 'test_helper'

class StatesIntegrationTest < Minitest::Test
  include IntegrationHelper

  # BRANCH, STATUS and FETCHED. The gone fixture fetched to prune its branch, so only its FETCHED
  # is a duration.
  EXPECTED = {
    'ahead' => %w[main Ahead <never>], 'behind' => %w[main Behind <never>], 'clean' => %w[main Clean <never>],
    'conflicted' => %w[main Conflicted <never>], 'detached' => %w[(detached) Detached <never>],
    'diverged' => %w[main Diverged <never>], 'gone' => ['feature', 'Gone', :age],
    'missing' => %w[<none> Missing <none>], 'plain' => %w[<none> NotARepo <none>],
    'staged' => %w[main Dirty <never>], 'stash' => %w[main Clean <never>], 'unborn' => %w[main Unborn <never>],
    'unstaged' => %w[main Dirty <never>], 'untracked' => %w[main Dirty <never>]
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
      assert_table [%w[NAME BRANCH STATUS FETCHED AGE], *EXPECTED.map { |name, cells| [name, *cells, :age] }], out
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
      assert_table [%w[NAME BRANCH STATUS FETCHED AGE], ['clean', '<none>', 'Unknown', '<none>', :age],
                    ['dirty', '<none>', 'Unknown', '<none>', :age], ['missing', '<none>', 'Missing', '<none>', :age]],
                   out
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
