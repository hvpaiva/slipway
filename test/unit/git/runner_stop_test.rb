# frozen_string_literal: true

require 'test_helper'
require 'slipway/git'
require 'tmpdir'

# A run that ends early, at the deadline or on an interrupt, stops git and the helpers in its group.
class GitRunnerStopTest < Minitest::Test
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

  def test_an_interrupted_run_prints_nothing_while_a_helper_holds_the_output_open
    fifo = File.join(@root, 'helper.pid')
    File.mkfifo(fifo)
    bin = fake_git(@root, %(sh -c 'trap "" TERM; echo $$ > "#{fifo}"; exec sleep 30' &\nwait))
    before = Thread.list

    with_env('PATH' => "#{bin}:#{ENV.fetch('PATH')}") do
      _, err = capture_io { interrupt_with_a_helper_left(fifo, before) }

      assert_empty err
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

  def test_a_per_call_timeout_kills_git_and_its_grandchild_at_that_deadline
    grandchild = File.join(@root, 'grandchild')
    bin = fake_git(@root, "sleep 60 &\necho $! > #{grandchild}\nexec sleep 60")

    with_env('PATH' => "#{bin}:#{ENV.fetch('PATH')}") do
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      error = assert_raises(Slipway::Git::Timeout) { @runner.run(@root, 'fetch', timeout: 0.5) }

      assert_in_delta 0.5, Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, 0.5
      assert_equal "#{@root}: git did not finish within 0.5 seconds", error.message
      assert gone?(Integer(File.read(grandchild))), 'the grandchild survived the deadline'
    end
  end

  def test_the_deadline_covers_a_helper_that_outlives_git_holding_its_output
    helper = File.join(@root, 'helper')
    bin = fake_git(@root, "sleep 30 &\necho $! > #{helper}\nexit 0")

    with_env('PATH' => "#{bin}:#{ENV.fetch('PATH')}") do
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      assert_raises(Slipway::Git::Timeout) { @runner.run(@root, 'fetch', timeout: 0.5) }

      assert_in_delta 0.5, Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, 0.5
      assert gone?(Integer(File.read(helper))), 'the helper survived the deadline'
    end
  end

  def test_an_interrupt_after_git_exits_kills_the_helper_holding_its_output
    pids = File.join(@root, 'pids')
    bin = fake_git(@root, "sleep 30 &\necho $$ $! > #{pids}\nexit 0")

    with_env('PATH' => "#{bin}:#{ENV.fetch('PATH')}") do
      thread = Thread.new { @runner.run(@root, 'fetch', timeout: 30) }
      thread.report_on_exception = false
      sleep 0.05 until File.exist?(pids) && File.read(pids).end_with?("\n")
      git, helper = File.read(pids).split.map { Integer(it) }

      assert gone?(git), 'git did not exit'
      thread.raise(Interrupt)

      assert_raises(Interrupt) { thread.join }
      assert gone?(helper), 'the helper survived the interrupt'
    end
  end

  # Git removes its lock files on TERM, so it gets TERM first; the group is then killed whether
  # or not git is still running.
  def test_the_deadline_sends_term_before_it_kills_the_group
    helper = File.join(@root, 'helper')
    trapped = File.join(@root, 'trapped')
    bin = fake_git(@root, <<~SH)
      trap 'touch #{trapped}; exit 143' TERM
      (trap '' TERM; exec sleep 60) >/dev/null 2>&1 &
      echo $! > #{helper}
      sleep 60 & wait $!
    SH

    with_env('PATH' => "#{bin}:#{ENV.fetch('PATH')}") do
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      assert_raises(Slipway::Git::Timeout) { @runner.run(@root, 'fetch', timeout: 0.5) }

      assert_in_delta 0.5, Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, 0.5
      assert_path_exists trapped
      assert gone?(Integer(File.read(helper))), 'a helper that ignores TERM survived the deadline'
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

  # The helper ignores TERM, so the pipes stay open until the group is killed, while the readers
  # still block on them; a reader that reported would print after the interrupt has left run.
  def interrupt_with_a_helper_left(fifo, before)
    running = Thread.new { @runner.run(@root, 'status') }
    running.report_on_exception = false
    helper = Integer(File.read(fifo))
    Thread.pass until running.stop?
    running.raise(Interrupt)
    assert_raises(Interrupt) { running.join }
    Thread.pass until (Thread.list - before).empty?
  ensure
    Process.kill('KILL', helper) if helper && !gone?(helper)
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
