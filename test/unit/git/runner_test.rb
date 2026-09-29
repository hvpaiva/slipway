# frozen_string_literal: true

require 'test_helper'
require 'slipway/git'
require 'tmpdir'

class GitRunnerTest < Minitest::Test
  include GitFixtures

  def setup
    @root = Dir.mktmpdir('slipway-runner-')
    @saved = replace_env(hermetic_env(@root))
    @runner = Slipway::Git::Runner.new
  end

  def teardown
    restore_env(@saved)
    FileUtils.remove_entry(@root)
  end

  def test_defaults_name_the_binary_and_a_ten_second_deadline
    assert_equal 'git', @runner.binary
    assert_in_delta 10.0, @runner.timeout
  end

  def test_run_returns_the_exit_status_and_both_streams
    dir = build_repo(File.join(@root, 'clean'), 'clean')

    result = @runner.run(dir, 'rev-parse', '--show-toplevel')

    assert_predicate result, :success?
    assert_equal 0, result.status
    assert_equal "#{File.realpath(dir)}\n", result.out
    assert_empty result.err
  end

  def test_git_failures_come_back_as_results_not_exceptions
    dir = build_repo(File.join(@root, 'plain'), 'plain_dir')

    result = @runner.run(dir, 'status')

    refute_predicate result, :success?
    assert_equal 128, result.status
    assert_match(/\Afatal: not a git repository/, result.err)
  end

  def test_the_path_is_expanded_before_git_sees_it
    dir = build_repo(File.join(@root, 'clean'), 'clean')

    result = @runner.run('~/clean', 'rev-parse', '--show-toplevel')

    assert_equal "#{File.realpath(dir)}\n", result.out
  end

  def test_an_inherited_git_dir_does_not_redirect_the_query
    clean = build_repo(File.join(@root, 'clean'), 'clean')
    staged = build_repo(File.join(@root, 'staged'), 'staged')

    with_env('GIT_DIR' => File.join(clean, '.git'), 'GIT_WORK_TREE' => clean) do
      assert_equal "#{File.realpath(staged)}\n", @runner.run(staged, 'rev-parse', '--show-toplevel').out
      assert_includes @runner.run(staged, 'status', '--porcelain=v2', '-z').out, 'new.txt'
    end
  end

  def test_the_child_environment_is_pinned
    bin = fake_git(@root, 'printf "%s|%s|%s|%s" "$LC_ALL" "$GIT_TERMINAL_PROMPT" "$GIT_OPTIONAL_LOCKS" ' \
                          '"${GIT_DIR-unset}"')

    with_env('PATH' => "#{bin}:#{ENV.fetch('PATH')}", 'GIT_DIR' => '/elsewhere', 'LC_ALL' => 'pt_BR.UTF-8') do
      assert_equal 'C|0|0|unset', @runner.run(@root, 'status').out
    end
  end

  def test_output_is_valid_utf8_whatever_bytes_git_prints
    dir = build_repo(File.join(@root, 'clean'), 'clean')
    begin
      File.write(File.join(dir, "caf\xE9.txt".b), "x\n")
    rescue Errno::EILSEQ
      skip 'this filesystem refuses file names that are not valid UTF-8'
    end

    result = @runner.run(dir, 'status', '--porcelain=v2', '-z')

    assert_equal Encoding::UTF_8, result.out.encoding
    assert_predicate result.out, :valid_encoding?
    assert_includes result.out, "? caf\uFFFD.txt"
  end

  def test_a_missing_binary_raises_not_installed
    runner = Slipway::Git::Runner.new(binary: 'slipway-missing-git')

    error = assert_raises(Slipway::Git::NotInstalled) { runner.run(@root, 'version') }

    assert_equal "#{@root}: git executable \"slipway-missing-git\" not found on PATH", error.message
    assert_equal @root, error.path
    assert_equal 1, error.exit_status
  end

  def test_a_git_ended_by_a_signal_reports_128_plus_the_signal_number
    bin = fake_git(@root, 'kill -TERM $$')

    with_env('PATH' => "#{bin}:#{ENV.fetch('PATH')}") do
      assert_equal 128 + Signal.list.fetch('TERM'), @runner.run(@root, 'status').status
    end
  end

  def test_env_adds_variables_but_cannot_change_the_pinned_ones
    bin = fake_git(@root, 'printf "%s|%s|%s" "$GIT_REFLOG_ACTION" "$LC_ALL" "${GIT_DIR-unset}"')
    env = { 'GIT_REFLOG_ACTION' => 'slipway sync', 'LC_ALL' => 'pt_BR.UTF-8', 'GIT_DIR' => '/elsewhere' }

    with_env('PATH' => "#{bin}:#{ENV.fetch('PATH')}") do
      assert_equal 'slipway sync|C|unset', @runner.run(@root, 'merge', env:).out
      assert_equal '|C|unset', @runner.run(@root, 'status').out
    end
  end

  def test_the_network_environment_is_the_frozen_constant_and_the_allowed_protocols
    names = %w[GIT_ASKPASS SSH_ASKPASS SSH_ASKPASS_REQUIRE GIT_ALLOW_PROTOCOL]
    bin = fake_git(@root, names.map { %(printf '%s\\n' "$#{it}") }.join("\n"))
    env = Slipway::Git::Runner.network_environment(%w[ssh https])

    with_env('PATH' => "#{bin}:#{ENV.fetch('PATH')}") do
      assert_equal env.values_at(*names), @runner.run(@root, 'fetch', env:).out.lines(chomp: true)
    end
    assert_equal Slipway::Git::Runner::NETWORK_ENVIRONMENT.merge('GIT_ALLOW_PROTOCOL' => 'ssh:https'), env
    assert_predicate Slipway::Git::Runner::NETWORK_ENVIRONMENT, :frozen?
    assert_equal [Slipway::Git::Runner::FALSE_PROGRAM, Slipway::Git::Runner::FALSE_PROGRAM, 'force'],
                 Slipway::Git::Runner::NETWORK_ENVIRONMENT.values
  end

  def test_the_askpass_is_an_absolute_false_that_exists_here
    program = Slipway::Git::Runner::FALSE_PROGRAM

    assert File.absolute_path?(program), "#{program} is not an absolute path"
    assert File.executable?(program), "#{program} cannot be run"
    refute system(program)
  end

  def test_false_program_takes_the_first_candidate_that_runs_and_else_the_first_path
    missing = File.join(@root, 'missing', 'false')
    present = File.join(fake_git(@root, 'exit 1'), 'git')

    assert_equal present, Slipway::Git::Runner.false_program([missing, present])
    assert_equal missing, Slipway::Git::Runner.false_program([missing, File.join(@root, 'absent')])
  end
end
