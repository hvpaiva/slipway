# frozen_string_literal: true

require 'test_helper'

class ViewsProjectTest < Minitest::Test
  include OutputHelper

  NOW = CommandsHelper::NOW
  FETCHED = CommandsHelper::FETCHED
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
      Last Fetch:  2026-09-29T11:48:00Z
    Last Commit:
      Hash:     a1b2c3d4e5f60718293a4b5c6d7e8f9012345678
      Author:   Ada Lovelace <ada@example.com>
      Date:     2026-09-29T11:15:00Z
      Subject:  initial commit
  TEXT

  def test_headers_add_group_first_wide_columns_and_labels_last
    view = Slipway::Views::Project

    assert_equal %w[NAME BRANCH STATUS FETCHED AGE], view.headers
    assert_equal %w[GROUP NAME BRANCH STATUS FETCHED AGE], view.headers(group: true)
    assert_equal %w[NAME BRANCH STATUS FETCHED AGE PATH HEAD LAST-COMMIT], view.headers(wide: true)
    assert_equal %w[GROUP NAME BRANCH STATUS FETCHED AGE PATH HEAD LAST-COMMIT LABELS],
                 view.headers(wide: true, group: true, labels: true)
  end

  def test_row_follows_the_headers_for_a_clean_repository
    inspection = inspected(CommandsHelper::CLEAN, commit: CommandsHelper::COMMIT)
    view = Slipway::Views::Project

    assert_equal %w[hldr main Clean 12m 3h], view.row(inspection, now: NOW)
    assert_equal ['personal', 'hldr', 'main', 'Clean', '12m', '3h', '~/dev/hldr', 'a1b2c3d', '45m',
                  'app=web,lang=rust'],
                 view.row(inspection, now: NOW, wide: true, group: true, labels: true)
  end

  def test_row_shows_detached_heads_and_leaves_unknown_cells_nil
    detached = inspected(CommandsHelper::DETACHED, commit: CommandsHelper::COMMIT)
    unborn = inspected(CommandsHelper::UNBORN)
    missing = Slipway::Inspection.failed(PROJECT.with(labels: {}), Slipway::Git::MissingPath.new('/x'))
    view = Slipway::Views::Project

    assert_equal ['hldr', '(detached)', 'Detached', '12m', '3h'], view.row(detached, now: NOW)
    assert_equal ['hldr', 'main', 'Unborn', '12m', '3h', '~/dev/hldr', nil, nil], view.row(unborn, now: NOW, wide: true)
    assert_equal ['hldr', nil, 'Missing', nil, '3h', '~/dev/hldr', nil, nil, nil],
                 view.row(missing, now: NOW, wide: true, labels: true)
  end

  def test_fetched_reads_never_for_a_repository_no_fetch_has_reached
    never = inspected(CommandsHelper::CLEAN, fetched_at: nil)
    skewed = inspected(CommandsHelper::CLEAN, fetched_at: NOW + 3600)

    assert_equal %w[hldr main Clean <never> 3h], Slipway::Views::Project.row(never, now: NOW)
    assert_equal '<invalid>', Slipway::Views::Project.row(skewed, now: NOW)[3]
  end

  def test_roles_paint_the_status_column_and_mute_a_fetch_that_never_ran
    roles = Slipway::Views::Project::ROLES

    assert_equal :status_success, roles.call('STATUS', 'Clean')
    assert_equal :status_danger, roles.call('STATUS', 'Missing')
    assert_equal :muted, roles.call('FETCHED', '<never>')
    assert_nil roles.call('FETCHED', '3h')
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
      Repository:   no such directory
      Last Commit:  <none>
    TEXT

    assert_equal expected, render(Slipway::Views::Project.describe(inspection, now: NOW))
  end

  def test_describe_shows_none_for_an_unborn_branch_without_upstream
    rendered = render(Slipway::Views::Project.describe(inspected(CommandsHelper::UNBORN), now: NOW))

    assert_includes rendered, "  Head:        <none>\n  Upstream:    <none>\n  Ahead:       <none>\n"
    assert_includes rendered, "Last Commit:  <none>\n"
  end

  def test_describe_mutes_a_fetch_that_never_ran
    inspection = inspected(CommandsHelper::CLEAN, fetched_at: nil)

    assert_includes render(Slipway::Views::Project.describe(inspection, now: NOW)), "  Last Fetch:  <never>\n"
    assert_includes render(Slipway::Views::Project.describe(inspection, now: NOW), colored_context),
                    "\e[36mLast Fetch\e[0m:  \e[90;3m<never>\e[0m\n"
  end

  def test_object_merges_the_manifest_with_a_status_hash
    inspection = inspected(CommandsHelper::CLEAN, commit: CommandsHelper::COMMIT, remote: 'r')
    expected = PROJECT.to_manifest.merge(
      'status' => { 'branch' => 'main', 'head' => 'a1b2c3d', 'upstream' => 'origin/main', 'ahead' => 0, 'behind' => 0,
                    'staged' => 0, 'unstaged' => 0, 'untracked' => 0, 'conflicted' => 0, 'stashes' => 0,
                    'state' => 'Clean', 'lastFetch' => '2026-09-29T11:48:00Z',
                    'lastCommit' => { 'hash' => CommandsHelper::SHA, 'author' => 'Ada Lovelace',
                                      'email' => 'ada@example.com', 'date' => '2026-09-29T11:15:00Z',
                                      'subject' => 'initial commit' } }
    )

    assert_equal expected, Slipway::Views::Project.object(inspection)
    assert_equal expected.fetch('status').keys, Slipway::Views::Project.object(inspection).fetch('status').keys
  end

  def test_object_leaves_out_the_status_fields_git_could_not_answer
    inspection = Slipway::Inspection.failed(PROJECT, Slipway::Git::NotARepository.new('/x'))
    unborn = inspected(CommandsHelper::UNBORN, fetched_at: nil)

    assert_equal({ 'state' => 'NotARepo' }, Slipway::Views::Project.object(inspection).fetch('status'))
    assert_equal %w[branch staged unstaged untracked conflicted stashes state],
                 Slipway::Views::Project.object(unborn).fetch('status').keys
  end

  def test_describe_adds_the_remedy_under_the_reason_when_the_error_has_one
    inspection = Slipway::Inspection.failed(PROJECT, Slipway::Git::UnsafeRepository.new('/srv/x y'))

    rendered = render(Slipway::Views::Project.describe(inspection, now: NOW))

    assert_includes rendered, "Repository:   repository has dubious ownership\n              " \
                              "Run 'git config --global --add safe.directory /srv/x\\ y' to trust it.\n"
  end

  def test_describe_and_rows_make_control_characters_visible
    commit = CommandsHelper::COMMIT.with(subject: "fix\e[2Jall", author: "Mallory\e]0;x\a")
    inspection = inspected(CommandsHelper::CLEAN, commit:)
    project = PROJECT.with(description: "nice\u0085done")

    rendered = render(Slipway::Views::Project.describe(inspection.with(project:), now: NOW))

    assert_includes rendered, "Description:  nice\uFFFDdone\n"
    assert_includes rendered, "  Author:   Mallory^[]0;x^G <ada@example.com>\n"
    assert_includes rendered, "  Subject:  fix^[[2Jall\n"
  end

  def test_describe_redacts_the_credentials_in_the_remote
    https = inspected(CommandsHelper::CLEAN, remote: 'https://ci-bot:s3cret@example.com/x.git')
    ssh = inspected(CommandsHelper::CLEAN, remote: 'ssh://git:s3cret@example.com/x.git')

    assert_includes render(Slipway::Views::Project.describe(https, now: NOW)),
                    "  Remote:      https://***@example.com/x.git\n"
    assert_includes render(Slipway::Views::Project.describe(ssh, now: NOW)),
                    "  Remote:      ssh://git:***@example.com/x.git\n"
  end

  def test_rows_and_objects_never_carry_the_remote
    inspection = inspected(CommandsHelper::CLEAN, commit: CommandsHelper::COMMIT,
                                                  remote: 'https://ci-bot:s3cret@forge.test/x.git')
    row = Slipway::Views::Project.row(inspection, now: NOW, wide: true, group: true, labels: true)

    refute_includes row.join(' '), 'forge.test'
    refute_includes Slipway::Views::Project.object(inspection).to_s, 'forge.test'
  end

  def test_object_makes_the_text_git_returned_plain
    commit = CommandsHelper::COMMIT.with(subject: "fix\e[2Jall", author: "Mallory\u202E", email: "m\e]0;x\a@x")
    inspection = inspected(CommandsHelper::CLEAN.with(branch: "main\u2066", upstream: "origin/main\e[8m"), commit:)

    status = Slipway::Views::Project.object(inspection).fetch('status')

    assert_equal ["main\uFFFD", 'origin/main^[[8m'], status.values_at('branch', 'upstream')
    assert_equal ["Mallory\uFFFD", 'm^[]0;x^G@x', 'fix^[[2Jall'],
                 status.fetch('lastCommit').values_at('author', 'email', 'subject')
    assert_equal [0, 'Clean'], status.values_at('ahead', 'state')
  end

  private

  def inspected(status, commit: nil, remote: nil, fetched_at: FETCHED)
    Slipway::Inspection.new(project: PROJECT, status:, commit:, remote:, fetched_at:,
                            state: Slipway::State.derive(status), error: nil)
  end

  def render(entries, context = plain_context) = Slipway::Output::Describe.new(context).render(entries)
end
