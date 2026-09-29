# frozen_string_literal: true

require 'test_helper'

class InspectorTest < Minitest::Test
  include GitFixtures

  NOW = Time.utc(2026, 9, 29, 12, 0, 0)

  def setup
    @home = Dir.mktmpdir('slipway-inspector-')
    @git = Slipway::Git::Fake.new
    @inspector = Slipway::Inspector.new(git: @git, clock: -> { NOW }, home: @home)
  end

  def teardown
    FileUtils.rm_rf(@home)
  end

  def test_a_clean_repository_yields_status_commit_remote_and_state
    project = repo('hldr', status: CommandsHelper::CLEAN, commit: CommandsHelper::COMMIT, remote: 'git@x:y.git')

    inspection = @inspector.inspect(project)

    assert_equal [CommandsHelper::CLEAN, CommandsHelper::COMMIT, 'git@x:y.git', 'Clean', nil],
                 [inspection.status, inspection.commit, inspection.remote, inspection.state, inspection.error]
    assert_same project, inspection.project
    assert_predicate inspection, :inspected?
  end

  def test_an_unborn_repository_is_not_asked_for_its_last_commit
    project = repo('fresh', status: CommandsHelper::UNBORN, commit: CommandsHelper::COMMIT)

    inspection = @inspector.inspect(project)

    assert_nil inspection.commit
    assert_equal 'Unborn', inspection.state
  end

  def test_a_path_that_is_not_a_directory_is_missing_without_asking_git
    project = Slipway::Project.new(name: 'gone', path: '~/dev/gone')
    @git.fail(File.join(@home, 'dev', 'gone'), Slipway::Git::Timeout)

    inspection = @inspector.inspect(project)

    assert_equal 'Missing', inspection.state
    assert_instance_of Slipway::Git::MissingPath, inspection.error
    assert_equal "#{File.join(@home, 'dev', 'gone')}: no such directory", inspection.error.message
    assert_equal [nil, nil, nil], [inspection.status, inspection.commit, inspection.remote]
    refute_predicate inspection, :inspected?
  end

  def test_git_errors_map_to_their_state_words
    failures = { 'plain' => Slipway::Git::NotARepository, 'theirs' => Slipway::Git::UnsafeRepository,
                 'slow' => Slipway::Git::Timeout, 'nogit' => Slipway::Git::NotInstalled }
    projects = failures.map { |name, error| failing(name, error) }

    states = projects.map { @inspector.inspect(it).state }

    assert_equal %w[NotARepo Unsafe Unknown Unknown], states
  end

  def test_inspect_all_keeps_the_input_order_with_fewer_workers_than_projects
    names = %w[a b c d e f g h i j k l]
    projects = names.map { repo(it, status: CommandsHelper::CLEAN) }
    pooled = Slipway::Inspector.new(git: @git, clock: -> { NOW }, home: @home, workers: 3)

    inspections = pooled.inspect_all(projects)

    assert_equal(names, inspections.map { it.project.name })
    assert_equal ['Clean'] * names.size, inspections.map(&:state)
    assert_empty pooled.warnings
  end

  def test_inspect_all_of_nothing_returns_nothing
    assert_empty @inspector.inspect_all([])
    assert_empty @inspector.warnings
  end

  def test_warnings_hold_one_reason_per_unknown_cause_without_the_paths
    projects = [failing('one', Slipway::Git::NotInstalled), failing('two', Slipway::Git::NotInstalled),
                failing('slow', Slipway::Git::Timeout), failing('plain', Slipway::Git::NotARepository),
                repo('ok', status: CommandsHelper::CLEAN)]

    @inspector.inspect_all(projects)

    assert_equal ['git executable "git" not found on PATH', 'git did not finish within 10 seconds'],
                 @inspector.warnings
    assert_predicate @inspector.warnings, :frozen?
    @inspector.inspect_all([projects.last])

    assert_empty @inspector.warnings
  end

  def test_expand_resolves_tilde_and_relative_paths_against_the_given_home
    assert_equal File.join(@home, 'dev', 'x'), @inspector.expand('~/dev/x')
    assert_equal @home, @inspector.expand('~')
    assert_equal File.join(@home, 'dev', 'x'), @inspector.expand('dev/x')
    assert_equal '/srv/x', @inspector.expand('/srv/../srv/x')
    assert_equal File.join(@home, '~x'), @inspector.expand('~x')
  end

  def test_inspect_without_a_project_is_the_ordinary_object_inspect
    assert_match(/\A#<Slipway::Inspector/, @inspector.inspect)
  end

  def test_a_real_repository_is_read_through_the_production_repository
    dir = build_repo(File.join(@home, 'dev', 'real'), 'untracked')
    inspector = Slipway::Inspector.new(git: Slipway::Git::Repository.new, clock: -> { NOW }, home: @home)
    project = Slipway::Project.new(name: 'real', path: '~/dev/real')

    inspection = with_env(hermetic_env(@home)) { inspector.inspect(project) }

    assert_equal 'Dirty', inspection.state
    assert_equal ['main', 1, 'initial commit', nil], [inspection.status.branch, inspection.status.untracked,
                                                      inspection.commit.subject, inspection.remote]
    assert_equal dir, inspector.expand(project.path)
  end

  private

  def repo(name, status:, commit: nil, remote: nil)
    directory = File.join(@home, 'dev', name)
    FileUtils.mkdir_p(directory)
    @git.add(directory, status:, commit:, remote:)
    Slipway::Project.new(name:, path: "~/dev/#{name}")
  end

  def failing(name, error)
    project = repo(name, status: CommandsHelper::UNBORN)
    @git.fail(File.join(@home, 'dev', name), error)
    project
  end
end
