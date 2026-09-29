# frozen_string_literal: true

require 'test_helper'

class DescribeIntegrationTest < Minitest::Test
  include IntegrationHelper

  SHA = '5bbaee2c60e94db1f64d04925d8365eec25d449b'
  LAST_COMMIT = <<~TEXT.freeze
    Last Commit:
      Hash:     #{SHA}
      Author:   Fixture <fixture@example.com>
      Date:     2023-11-14T22:13:20Z
      Subject:  initial commit
  TEXT
  CLEAN = <<~TEXT.freeze
    Name:         clean
    Group:        default
    Labels:       lang=rust
                  tier=web
    Created:      #{CREATED}
    Age:          <age>
    Path:         ~/dev/clean
    Description:  A clean one
    Status:       Clean
    Repository:
      Branch:      main
      Head:        5bbaee2
      Upstream:    <none>
      Ahead:       <none>
      Behind:      <none>
      Staged:      0
      Unstaged:    0
      Untracked:   0
      Conflicted:  0
      Stashes:     0
      Remote:      <none>
    #{LAST_COMMIT.chomp}
  TEXT

  THREE = <<~TEXT.freeze
    Name:         gone
    Group:        default
    Labels:       <none>
    Created:      #{CREATED}
    Age:          <age>
    Path:         ~/dev/gone
    Description:  <none>
    Status:       Missing
    Repository:   no such directory
    Last Commit:  <none>

    Name:         plain
    Group:        default
    Labels:       <none>
    Created:      #{CREATED}
    Age:          <age>
    Path:         ~/dev/plain
    Description:  <none>
    Status:       NotARepo
    Repository:   not a git repository
    Last Commit:  <none>

    Name:         unborn
    Group:        default
    Labels:       <none>
    Created:      #{CREATED}
    Age:          <age>
    Path:         ~/dev/unborn
    Description:  <none>
    Status:       Unborn
    Repository:
      Branch:      main
      Head:        <none>
      Upstream:    <none>
      Ahead:       <none>
      Behind:      <none>
      Staged:      0
      Unstaged:    0
      Untracked:   0
      Conflicted:  0
      Stashes:     0
      Remote:      <none>
    Last Commit:  <none>
  TEXT

  BEHIND = <<~TEXT.freeze
    Name:         behind
    Group:        work
    Labels:       <none>
    Created:      #{CREATED}
    Age:          <age>
    Path:         ~/dev/behind
    Description:  <none>
    Status:       Behind
    Repository:
      Branch:      main
      Head:        5bbaee2
      Upstream:    origin/main
      Ahead:       0
      Behind:      1
      Staged:      0
      Unstaged:    0
      Untracked:   0
      Conflicted:  0
      Stashes:     0
      Remote:      <home>/dev/behind-origin.git
    #{LAST_COMMIT.chomp}
  TEXT

  GROUPS = <<~TEXT.freeze
    Name:         default
    Labels:       <none>
    Created:      #{CREATED}
    Age:          <age>
    Description:  <none>
    Projects:     1

    Name:         work
    Labels:       <none>
    Created:      #{CREATED}
    Age:          <age>
    Description:  Day job
    Projects:     1
  TEXT

  def expand(text, env) = text.gsub('<home>', env['HOME'])

  def test_a_project_prints_every_field_then_the_repository_and_its_last_commit
    with_home do |env|
      seed(env, manifest('Project', 'clean', path: repo(env, 'clean'), labels: { 'lang' => 'rust', 'tier' => 'web' },
                                             description: 'A clean one'))
      status, out, err = slipway('describe', 'project', 'clean', env:)

      assert_equal [0, ''], [status, err]
      assert_equal expand(CLEAN, env), scrub_age(out)
    end
  end

  def test_several_objects_are_separated_by_a_blank_line_and_failures_name_their_reason
    with_home do |env|
      seed(env, manifest('Project', 'gone', path: repo(env, 'gone', nil)),
           manifest('Project', 'plain', path: repo(env, 'plain', 'plain_dir')),
           manifest('Project', 'unborn', path: repo(env, 'unborn', 'unborn')))
      status, out, err = slipway('describe', 'projects', 'gone', 'plain', 'unborn', env:)

      assert_equal [0, ''], [status, err]
      assert_equal expand(THREE, env), scrub_age(out)
    end
  end

  def test_a_tracking_branch_shows_upstream_counts_and_remote
    with_home do |env|
      seed(env, manifest('Group', 'work'),
           manifest('Project', 'behind', group: 'work', path: repo(env, 'behind', 'behind')))
      status, out, err = slipway('describe', 'project', 'behind', '-n', 'work', env:)

      assert_equal [0, ''], [status, err]
      assert_equal expand(BEHIND, env), scrub_age(out)
    end
  end

  def test_a_selector_and_all_groups_pick_the_objects
    with_home do |env|
      seed(env, manifest('Group', 'work'),
           manifest('Project', 'clean', path: repo(env, 'clean'), labels: { 'lang' => 'rust' }),
           manifest('Project', 'other', group: 'work', path: repo(env, 'other'), labels: { 'lang' => 'rust' }),
           manifest('Project', 'dirty', path: repo(env, 'dirty', 'staged'), labels: { 'lang' => 'go' }))
      _, out, = slipway('describe', 'projects', '-l', 'lang=rust', '-A', env:)

      assert_equal %w[clean other], out.scan(/^Name: +(\S+)$/).flatten
      assert_equal %w[default work], out.scan(/^Group: +(\S+)$/).flatten
      assert_equal 1, out.scan(/^\n/).size
    end
  end

  def test_groups_show_their_project_count
    with_home do |env|
      seed(env, manifest('Group', 'default'), manifest('Group', 'work', description: 'Day job'),
           manifest('Project', 'clean', path: repo(env, 'clean')),
           manifest('Project', 'api', group: 'work', path: repo(env, 'api', nil)))
      status, out, err = slipway('describe', 'groups', env:)

      assert_equal [0, ''], [status, err]
      assert_equal expand(GROUPS, env), scrub_age(out)
      assert_equal out.lines[7..].join, slipway!('describe', 'group', 'work', env:)
    end
  end

  def test_nothing_selected_and_unknown_names
    with_home do |env|
      seed(env, manifest('Group', 'work'))

      assert_equal [0, '', "No resources found in empty group.\n"], slipway('describe', 'projects', '-n', 'empty', env:)
      assert_equal [0, '', "No resources found.\n"], slipway('describe', 'groups', '-l', 'a=b', env:)
      assert_equal [1, '', "error: projects \"x\" not found\n"], slipway('describe', 'project', 'x', env:)
    end
  end
end
