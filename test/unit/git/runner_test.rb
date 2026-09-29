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

  def test_a_slow_git_is_killed_with_its_children_and_reported_as_a_timeout
    pids = File.join(@root, 'pids')
    bin = fake_git(@root, "echo $$ > #{pids}\nsleep 30 &\necho $! >> #{pids}\nwait")
    runner = Slipway::Git::Runner.new(timeout: 0.2)

    with_env('PATH' => "#{bin}:#{ENV.fetch('PATH')}") do
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      error = assert_raises(Slipway::Git::Timeout) { runner.run(@root, 'status') }

      assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 2
      assert_equal "#{@root}: git did not finish within 0.2 seconds", error.message
      assert_equal 2, File.read(pids).split.size
      File.read(pids).split.each { assert gone?(Integer(it)), "process #{it} survived the kill" }
    end
  end

  def test_an_interrupted_run_kills_the_git_it_started
    pids = File.join(@root, 'pids')
    bin = fake_git(@root, "echo $$ > #{pids}\nexec sleep 30")

    with_env('PATH' => "#{bin}:#{ENV.fetch('PATH')}") do
      thread = Thread.new { @runner.run(@root, 'status') }
      thread.report_on_exception = false
      sleep 0.05 until File.exist?(pids) && !File.empty?(pids)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      thread.raise(Interrupt)

      assert_raises(Interrupt) { thread.join }
      assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 2
      assert gone?(Integer(File.read(pids))), 'git survived the interrupt'
    end
  end

  def test_an_interrupted_run_kills_a_git_that_survives_term
    fifo = File.join(@root, 'git.pid')
    File.mkfifo(fifo)
    bin = fake_git(@root, %(trap '' TERM; echo $$ > "#{fifo}"; exec sleep 30))

    with_env('PATH' => "#{bin}:#{ENV.fetch('PATH')}") do
      running = Thread.new { @runner.run(@root, 'status') }
      running.report_on_exception = false
      pid = Integer(File.read(fifo))
      Thread.pass until running.stop?
      running.raise(Interrupt)

      assert_raises(Interrupt, 'the run waited for a git that ignores TERM') { running.join(5) }
      assert gone?(pid), 'git outlived an interrupted run'
    ensure
      Process.kill('KILL', pid) if pid && !gone?(pid)
    end
  end

  def test_an_interrupted_run_still_raises_the_interrupt_when_the_group_answers_eperm
    pids = File.join(@root, 'pids')
    bin = fake_git(@root, "echo $$ > #{pids}\nexec sleep 30")

    with_env('PATH' => "#{bin}:#{ENV.fetch('PATH')}") do
      thread = Thread.new { @runner.run(@root, 'status') }
      thread.report_on_exception = false
      sleep 0.05 until File.exist?(pids) && !File.empty?(pids)
      answering_eperm_to_term do |refused|
        thread.raise(Interrupt)

        assert_raises(Interrupt) { thread.join(5) }
        assert_equal [-Integer(File.read(pids))], refused
      end
    end
  end

  def test_a_run_killed_as_git_starts_still_stops_it
    bin = fake_git(@root, 'exec sleep 30')
    started = Queue.new

    with_env('PATH' => "#{bin}:#{ENV.fetch('PATH')}") do
      gate = Queue.new
      running = Thread.new { gate.pop && @runner.run(@root, 'status') }
      killing_after_detach(running, started) do
        gate << true
        running.join(5)
      end
      pid = started.pop

      assert gone?(pid), 'git survived a kill that landed before the block'
    ensure
      Process.kill('KILL', pid) if pid && !gone?(pid)
    end
  end

  def test_a_git_ended_by_a_signal_reports_128_plus_the_signal_number
    bin = fake_git(@root, 'kill -TERM $$')

    with_env('PATH' => "#{bin}:#{ENV.fetch('PATH')}") do
      assert_equal 128 + Signal.list.fetch('TERM'), @runner.run(@root, 'status').status
    end
  end

  private

  # Stands in for macOS, which answers EPERM once every process left in the group has exited
  # but is not yet reaped: the TERM is sent, so git ends, and then the call fails as it does there.
  def answering_eperm_to_term
    kill = Process.method(:kill)
    refused = []
    Process.singleton_class.remove_method(:kill)
    Process.define_singleton_method(:kill) do |signal, pid|
      refused << pid if signal == 'TERM' && pid.negative?
      kill.call(signal, pid).tap { raise Errno::EPERM if refused.include?(pid) }
    end
    yield refused
  ensure
    Process.singleton_class.remove_method(:kill)
    Process.define_singleton_method(:kill, kill)
  end

  # The kill is queued the moment Process.detach returns, before Open3 yields to the block, and
  # joining the killer is an interrupt check, so an unmasked kill lands right there.
  def killing_after_detach(target, started, &)
    trace = TracePoint.new(:c_return) do |call|
      next unless call.method_id == :detach

      started << call.return_value.pid
      Thread.new { target.kill }.join
    end
    trace.enable(target_thread: target, &)
  end

  # A killed grandchild lingers as a zombie until its new parent reaps it, so poll for a moment.
  def gone?(pid)
    20.times do
      Process.kill(0, pid)
      sleep 0.05
    end
    false
  rescue Errno::ESRCH
    true
  end
end
