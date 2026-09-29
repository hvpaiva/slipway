# frozen_string_literal: true

require 'test_helper'

class InspectorTest < Minitest::Test
  include GitFixtures

  NOW = Time.utc(2026, 9, 29, 12, 0, 0)
  PID_FIFO = 'git.pid'

  def setup
    @home = Dir.mktmpdir('slipway-inspector-')
    @git = Slipway::Git::Fake.new
    @inspector = Slipway::Inspector.new(git: @git, clock: -> { NOW }, home: @home)
  end

  def teardown
    FileUtils.rm_rf(@home)
  end

  def test_a_clean_repository_yields_status_commit_remote_fetch_time_and_state
    project = repo('hldr', status: CommandsHelper::CLEAN, commit: CommandsHelper::COMMIT, remote: 'git@x:y.git',
                           fetched_at: CommandsHelper::FETCHED)

    inspection = @inspector.examine(project)

    assert_equal [CommandsHelper::CLEAN, CommandsHelper::COMMIT, 'git@x:y.git', CommandsHelper::FETCHED, 'Clean', nil],
                 [inspection.status, inspection.commit, inspection.remote, inspection.fetched_at, inspection.state,
                  inspection.error]
    assert_same project, inspection.project
  end

  def test_an_unborn_repository_is_not_asked_for_its_last_commit
    project = repo('fresh', status: CommandsHelper::UNBORN, commit: CommandsHelper::COMMIT)

    inspection = @inspector.examine(project)

    assert_nil inspection.commit
    assert_equal 'Unborn', inspection.state
  end

  def test_a_path_that_is_not_a_directory_is_missing_without_asking_git
    project = Slipway::Project.new(name: 'gone', path: '~/dev/gone')
    @git.fail(File.join(@home, 'dev', 'gone'), Slipway::Git::Timeout)

    inspection = @inspector.examine(project)

    assert_equal 'Missing', inspection.state
    assert_instance_of Slipway::Git::MissingPath, inspection.error
    assert_equal "#{File.join(@home, 'dev', 'gone')}: no such directory", inspection.error.message
    assert_equal [nil, nil, nil], [inspection.status, inspection.commit, inspection.remote]
  end

  def test_a_relative_path_is_missing_and_says_why_instead_of_being_resolved_against_home
    FileUtils.mkdir_p(File.join(@home, 'dev', 'x'))
    @git.add(File.join(@home, 'dev', 'x'), status: CommandsHelper::CLEAN)
    inspections = ['dev/x', '.', '', '~x'].map { @inspector.examine(Slipway::Project.new(name: 'rel', path: it)) }

    assert_equal ['Missing'] * 4, inspections.map(&:state)
    assert_equal 'dev/x: relative path; register an absolute path or one starting with ~/',
                 inspections.first.error.message
    assert_instance_of Slipway::Git::RelativePath, inspections.first.error
  end

  def test_git_errors_map_to_their_state_words
    failures = { 'plain' => Slipway::Git::NotARepository, 'theirs' => Slipway::Git::UnsafeRepository,
                 'slow' => Slipway::Git::Timeout, 'nogit' => Slipway::Git::NotInstalled }
    projects = failures.map { |name, error| failing(name, error) }

    states = projects.map { @inspector.examine(it).state }

    assert_equal %w[NotARepo Unsafe Unknown Unknown], states
  end

  def test_any_other_failure_while_reading_becomes_unknown_with_the_cause_in_the_warning
    project = failing('odd', ArgumentError.new('invalid value for Integer(): "many"'))

    batch = @inspector.examine_all([project])

    assert_equal 'Unknown', batch.inspections.first.state
    assert_instance_of Slipway::Git::Error, batch.inspections.first.error
    assert_equal ['git could not be read: ArgumentError: invalid value for Integer(): "many"'], batch.warnings
  end

  def test_examine_all_keeps_the_input_order_with_fewer_workers_than_projects
    names = %w[a b c d e f g h i j k l]
    projects = names.map { repo(it, status: CommandsHelper::CLEAN) }
    pooled = Slipway::Inspector.new(git: @git, clock: -> { NOW }, home: @home, workers: 3)

    batch = pooled.examine_all(projects)

    assert_equal(names, batch.inspections.map { it.project.name })
    assert_equal ['Clean'] * names.size, batch.inspections.map(&:state)
    assert_empty batch.warnings
    assert_predicate batch.inspections, :frozen?
  end

  def test_examine_all_of_nothing_returns_an_empty_batch
    batch = @inspector.examine_all([])

    assert_empty batch.inspections
    assert_empty batch.warnings
  end

  def test_warnings_hold_one_reason_per_unknown_cause_without_the_paths
    projects = [failing('one', Slipway::Git::NotInstalled), failing('two', Slipway::Git::NotInstalled),
                failing('slow', Slipway::Git::Timeout), failing('plain', Slipway::Git::NotARepository),
                repo('ok', status: CommandsHelper::CLEAN)]

    batch = @inspector.examine_all(projects)

    assert_equal ['git executable "git" not found on PATH', 'git did not finish within 10 seconds'], batch.warnings
    assert_predicate batch.warnings, :frozen?
    assert_empty @inspector.examine_all([projects.last]).warnings
  end

  def test_a_real_repository_is_read_through_the_production_repository
    build_repo(File.join(@home, 'dev', 'real'), 'untracked')
    inspector = Slipway::Inspector.new(git: Slipway::Git::Repository.new, clock: -> { NOW }, home: @home)
    project = Slipway::Project.new(name: 'real', path: '~/dev/real')

    inspection = with_env(hermetic_env(@home)) { inspector.examine(project) }

    assert_equal 'Dirty', inspection.state
    assert_equal ['main', 1, 'initial commit', nil, nil],
                 [inspection.status.branch, inspection.status.untracked, inspection.commit.subject, inspection.remote,
                  inspection.fetched_at]
  end

  def test_a_directory_inside_another_repository_is_not_a_repository_of_its_own
    outer = build_repo(File.join(@home, 'dev', 'outer'), 'clean')
    FileUtils.mkdir_p(File.join(outer, 'notarepo', 'deeper'))
    inspector = Slipway::Inspector.new(git: Slipway::Git::Repository.new, clock: -> { NOW }, home: @home)
    project = Slipway::Project.new(name: 'sub', path: '~/dev/outer/notarepo/deeper')

    inspection = with_env(hermetic_env(@home)) { inspector.examine(project) }

    assert_equal 'NotARepo', inspection.state
    assert_equal 'Clean', with_env(hermetic_env(@home)) { inspector.examine(project.with(path: outer)) }.state
  end

  def test_an_interrupted_examine_all_leaves_no_git_running
    bin = fake_git(@home, %(echo $$ > "$2/#{PID_FIFO}"\nexec sleep 30))
    projects = %w[one two].map { parked(it) }
    inspector = Slipway::Inspector.new(git: Slipway::Git::Repository.new, clock: -> { NOW }, home: @home)

    with_env('PATH' => "#{bin}:#{ENV.fetch('PATH')}") do
      examining = Thread.new { inspector.examine_all(projects) }
      examining.report_on_exception = false
      pids = interrupt_while_git_runs(examining, projects)

      assert_raises(Interrupt) { examining.join(5) }
      pids.each { |pid| assert_raises(Errno::ESRCH, "git #{pid} outlived the interrupt") { Process.kill(0, pid) } }
    end
  end

  private

  def repo(name, status:, commit: nil, remote: nil, fetched_at: nil)
    directory = File.join(@home, 'dev', name)
    FileUtils.mkdir_p(directory)
    @git.add(directory, status:, commit:, remote:, fetched_at:)
    Slipway::Project.new(name:, path: "~/dev/#{name}")
  end

  def failing(name, error)
    project = repo(name, status: CommandsHelper::UNBORN)
    @git.fail(File.join(@home, 'dev', name), error)
    project
  end

  def parked(name)
    directory = File.join(@home, 'dev', name)
    FileUtils.mkdir_p(directory)
    File.mkfifo(File.join(directory, PID_FIFO))
    Slipway::Project.new(name:, path: "~/dev/#{name}")
  end

  # Reading a FIFO waits for the git that writes it, and a stopped thread is parked in the pool,
  # so the interrupt lands while every git is running.
  def interrupt_while_git_runs(thread, projects)
    pids = projects.map { Integer(File.read(File.join(@home, 'dev', it.name, PID_FIFO))) }
    Thread.pass until thread.stop?

    pids.each { assert_equal 1, Process.kill(0, it) }
    thread.raise(Interrupt)
    pids
  end
end
