# frozen_string_literal: true

require 'test_helper'

class ViewsProjectTest < Minitest::Test
  include OutputHelper

  NOW = CommandsHelper::NOW
  PROJECT = Slipway::Project.new(name: 'hldr', group: 'personal', labels: { 'lang' => 'rust', 'app' => 'web' },
                                 created_at: CommandsHelper::CREATED, path: '~/dev/hldr', description: 'Site')
  DIRTY_DESCRIBE = <<~TEXT
    Name:         hldr
    Group:        personal
    Labels:       app=web
                  lang=rust
    Created:      2026-09-29T09:00:00Z
    Age:          3h
    Path:         ~/dev/hldr
    Description:  Site
    Status:       Dirty
    Repository:
      Branch:      main
      Head:        a1b2c3d
      Upstream:    origin/main
      Ahead:       0
      Behind:      0
      Staged:      1
      Unstaged:    2
      Untracked:   3
      Conflicted:  0
      Stashes:     1
      Remote:      git@github.com:h/hldr.git
    Last Commit:
      Hash:     a1b2c3d4e5f60718293a4b5c6d7e8f9012345678
      Author:   Ada Lovelace <ada@example.com>
      Date:     2026-09-29T11:15:00Z
      Subject:  initial commit
  TEXT

  def test_headers_add_group_first_wide_columns_and_labels_last
    view = Slipway::Views::Project

    assert_equal %w[NAME BRANCH STATUS AGE], view.headers
    assert_equal %w[GROUP NAME BRANCH STATUS AGE], view.headers(group: true)
    assert_equal %w[NAME BRANCH STATUS AGE PATH HEAD LAST-COMMIT], view.headers(wide: true)
    assert_equal %w[GROUP NAME BRANCH STATUS AGE PATH HEAD LAST-COMMIT LABELS],
                 view.headers(wide: true, group: true, labels: true)
  end

  def test_row_follows_the_headers_for_a_clean_repository
    inspection = inspected(CommandsHelper::CLEAN, commit: CommandsHelper::COMMIT)
    view = Slipway::Views::Project

    assert_equal %w[hldr main Clean 3h], view.row(inspection, now: NOW)
    assert_equal ['personal', 'hldr', 'main', 'Clean', '3h', '~/dev/hldr', 'a1b2c3d', '45m', 'app=web,lang=rust'],
                 view.row(inspection, now: NOW, wide: true, group: true, labels: true)
  end

  def test_row_shows_detached_heads_and_leaves_unknown_cells_nil
    detached = inspected(CommandsHelper::DETACHED, commit: CommandsHelper::COMMIT)
    unborn = inspected(CommandsHelper::UNBORN)
    missing = Slipway::Inspection.failed(PROJECT.with(labels: {}), Slipway::Git::MissingPath.new('/x'))
    view = Slipway::Views::Project

    assert_equal ['hldr', '(detached)', 'Detached', '3h'], view.row(detached, now: NOW)
    assert_equal ['hldr', 'main', 'Unborn', '3h', '~/dev/hldr', nil, nil], view.row(unborn, now: NOW, wide: true)
    assert_equal ['hldr', nil, 'Missing', '3h', '~/dev/hldr', nil, nil, nil],
                 view.row(missing, now: NOW, wide: true, labels: true)
  end

  def test_roles_paint_only_the_status_column
    roles = Slipway::Views::Project.roles

    assert_equal :status_success, roles.call('STATUS', 'Clean')
    assert_equal :status_danger, roles.call('STATUS', 'Missing')
    assert_nil roles.call('NAME', 'Clean')
  end

  def test_describe_lists_the_manifest_the_repository_and_the_last_commit
    inspection = inspected(CommandsHelper::DIRTY, commit: CommandsHelper::COMMIT, remote: 'git@github.com:h/hldr.git')

    assert_equal DIRTY_DESCRIBE, render(Slipway::Views::Project.describe(inspection, now: NOW))
  end

  def test_describe_paints_the_status_with_its_state_role
    inspection = inspected(CommandsHelper::CLEAN, commit: CommandsHelper::COMMIT)

    rendered = render(Slipway::Views::Project.describe(inspection, now: NOW), colored_context)

    assert_includes rendered, "\e[96mStatus\e[0m:       \e[32mClean\e[0m\n"
  end

  def test_describe_replaces_the_repository_with_the_error_when_git_could_not_answer
    project = Slipway::Project.new(name: 'gone', path: '~/dev/gone', created_at: CommandsHelper::CREATED)
    inspection = Slipway::Inspection.failed(project, Slipway::Git::MissingPath.new('/home/me/dev/gone'))
    expected = <<~TEXT
      Name:         gone
      Group:        default
      Labels:       <none>
      Created:      2026-09-29T09:00:00Z
      Age:          3h
      Path:         ~/dev/gone
      Description:  <none>
      Status:       Missing
      Repository:   /home/me/dev/gone: no such directory
      Last Commit:  <none>
    TEXT

    assert_equal expected, render(Slipway::Views::Project.describe(inspection, now: NOW))
  end

  def test_describe_shows_none_for_an_unborn_branch_without_upstream
    rendered = render(Slipway::Views::Project.describe(inspected(CommandsHelper::UNBORN), now: NOW))

    assert_includes rendered, "  Head:        <none>\n  Upstream:    <none>\n  Ahead:       <none>\n"
    assert_includes rendered, "Last Commit:  <none>\n"
  end

  def test_object_merges_the_manifest_with_a_status_hash
    inspection = inspected(CommandsHelper::CLEAN, commit: CommandsHelper::COMMIT, remote: 'r')
    expected = PROJECT.to_manifest.merge(
      'status' => { 'branch' => 'main', 'head' => 'a1b2c3d', 'upstream' => 'origin/main', 'ahead' => 0, 'behind' => 0,
                    'staged' => 0, 'unstaged' => 0, 'untracked' => 0, 'conflicted' => 0, 'stashes' => 0,
                    'state' => 'Clean',
                    'lastCommit' => { 'hash' => CommandsHelper::SHA, 'author' => 'Ada Lovelace',
                                      'email' => 'ada@example.com', 'date' => '2026-09-29T11:15:00Z',
                                      'subject' => 'initial commit' } }
    )

    assert_equal expected, Slipway::Views::Project.object(inspection)
    assert_equal expected.fetch('status').keys, Slipway::Views::Project.object(inspection).fetch('status').keys
  end

  def test_object_keeps_the_status_keys_with_nil_values_when_git_could_not_answer
    inspection = Slipway::Inspection.failed(PROJECT, Slipway::Git::NotARepository.new('/x'))

    status = Slipway::Views::Project.object(inspection).fetch('status')

    assert_equal 'NotARepo', status.fetch('state')
    assert_nil status.fetch('lastCommit')
    assert_equal 12, status.size
    assert_equal ['state'], status.compact.keys
  end

  private

  def inspected(status, commit: nil, remote: nil)
    Slipway::Inspection.new(project: PROJECT, status:, commit:, remote:, state: Slipway::State.derive(status),
                            error: nil)
  end

  def render(entries, context = plain_context) = Slipway::Output::Describe.new(context).render(entries)
end
