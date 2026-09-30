# frozen_string_literal: true

require 'test_helper'

# fetch as a process: the pipes it writes to, a reader that leaves, and an interrupt.
class FetchProcessIntegrationTest < Minitest::Test
  include IntegrationHelper

  # The fixtures' origins are local paths, which git reaches over the file transport.
  PROTOCOLS = { 'SLIPWAY_PROTOCOLS' => 'ssh:https:file' }.freeze

  # Held back until exit, the lines would land after the summary, which stderr writes at once.
  def test_the_summary_follows_the_lines_when_both_streams_share_a_pipe
    with_home do |env|
      seed(env, manifest('Project', 'first', path: repo(env, 'first', nil)),
           manifest('Project', 'second', path: repo(env, 'second', nil)))
      out, status = Open3.capture2e(env, *COMMAND, 'fetch', unsetenv_others: true)

      assert_equal [0, "project/first skipped (Missing)\n  ~/dev/first: no such directory\n" \
                       "project/second skipped (Missing)\n  ~/dev/second: no such directory\n" \
                       "2 projects: 2 skipped\n"],
                   [status.exitstatus, out]
    end
  end

  # Ruby also flushes stdout before it spawns, so the first fetch ends after the last git started.
  def test_a_result_reaches_a_pipe_while_a_later_project_still_fetches
    with_home do |env|
      seed(env, manifest('Project', 'first', path: repo(env, 'first', 'synced')),
           manifest('Project', 'second', path: repo(env, 'second', 'synced')))
      pid_file = File.join(env['HOME'], 'git.pid')
      env = env.merge(PROTOCOLS, 'PATH' => "#{hanging_git(env, pid_file, hang: 'second')}:#{env.fetch('PATH')}")

      IO.pipe do |reader, writer|
        status, = interrupt_fetch(env, pid_file, out: writer) do
          writer.close

          assert reader.wait_readable(10), 'nothing reached the pipe while the second project fetched'
          assert_match %r{\Aproject/first (?:unchanged|fetched)\n\z}, reader.gets
        end

        assert_equal 130, status
      end
    end
  end

  # Ruby flushes stdout before it spawns, so a line the closed pipe refused must not wait in a
  # buffer: every later git would fail to start.
  def test_a_reader_that_goes_away_leaves_the_later_projects_fetched_and_the_status_true
    with_home do |env|
      seed(env, *%w[a b c].map { manifest('Project', it, path: repo(env, it, 'stale')) })
      FileUtils.rm_rf(File.join(env['HOME'], 'dev', 'c-origin.git'))
      marker = File.join(env['HOME'], 'release')
      path = "#{held_git(env, marker, hold: 'b')}:#{env.fetch('PATH')}"
      env = env.merge(PROTOCOLS, 'SLIPWAY_PARALLEL' => '1', 'PATH' => path)

      assert_equal [1, "3 projects: 2 fetched, 1 failed\n"], fetch_to_a_closed_reader(env, marker)
      assert_equal(%w[Behind Behind Clean], table(slipway!('get', 'projects', env:)).drop(1).map { it[2] })
    end
  end

  def test_an_interrupt_ends_the_run_with_status_130_and_leaves_no_git_behind
    with_home do |env|
      seed(env, manifest('Project', 'stale', path: repo(env, 'stale', 'stale')))
      pid_file = File.join(env['HOME'], 'git.pid')
      env = env.merge(PROTOCOLS, 'PATH' => "#{hanging_git(env, pid_file)}:#{env.fetch('PATH')}")

      status, err, git = interrupt_fetch(env, pid_file)

      assert_equal [130, "\n"], [status, err]
      assert gone?(git), "git #{git} outlived the interrupted fetch"
    end
  end

  private

  # A git that records its pid and hangs on a fetch in the directory named +hang+, or in any
  # directory, and hands every other command to the real one. A fetch it does not hold waits for
  # the one it holds to start. Runner passes the directory as the argument after -C.
  def hanging_git(env, pid_file, hang: nil)
    fake_git(env.fetch('HOME'), <<~SH)
      for arg do
        [ "$arg" = fetch ] || continue
        case "$2" in
          #{hang ? "*/#{hang}" : '*'}) echo $$ > '#{pid_file}'; exec sleep 30 ;;
        esac
        until [ -s '#{pid_file}' ]; do sleep 1; done
      done
      exec '#{real_git}' "$@"
    SH
  end

  # A git that holds a fetch in the directory named +hold+ until +marker+ exists.
  def held_git(env, marker, hold:)
    fake_git(env.fetch('HOME'), <<~SH)
      for arg do
        [ "$arg" = fetch ] || continue
        case "$2" in */#{hold}) until [ -e '#{marker}' ]; do sleep 0.1; done ;; esac
      done
      exec '#{real_git}' "$@"
    SH
  end

  def real_git
    ENV.fetch('PATH').split(File::PATH_SEPARATOR).map { File.join(it, 'git') }.find { File.executable?(it) }
  end

  # The reader leaves after the first line, and the held fetch is let go only then, so the
  # later results meet a closed pipe.
  def fetch_to_a_closed_reader(env, marker)
    err = File.join(env.fetch('HOME'), 'fetch.err')
    IO.pipe do |reader, writer|
      pid = Process.spawn(env, *COMMAND, 'fetch', unsetenv_others: true, out: writer, err:)
      writer.close

      assert reader.wait_readable(10), 'the first project never printed'
      reader.gets
      reader.close
      FileUtils.touch(marker)
      [exit_status(pid), File.read(err)]
    ensure
      stop(pid) if pid
    end
  end

  # SIGINT goes to slipway alone, as a terminal's would: git runs in a process group of its own,
  # so only slipway can stop it.
  def interrupt_fetch(env, pid_file, out: File::NULL)
    err = File.join(env.fetch('HOME'), 'fetch.err')
    pid = Process.spawn(env, *COMMAND, 'fetch', unsetenv_others: true, out:, err:)
    git = wait_for_pid(pid_file)
    yield if block_given?
    Process.kill('INT', pid)
    [exit_status(pid), File.read(err), git]
  ensure
    [pid, git].compact.each { stop(it) }
  end

  def wait_for_pid(file)
    deadline = clock + 10
    until File.file?(file) && File.read(file).end_with?("\n")
      raise 'git fetch never started' if clock > deadline

      sleep 0.05
    end
    Integer(File.read(file))
  end

  def exit_status(pid)
    deadline = clock + 10
    loop do
      _, status = Process.wait2(pid, Process::WNOHANG)
      return status.exitstatus if status
      raise "slipway #{pid} was still running 10 seconds after SIGINT" if clock > deadline

      sleep 0.05
    end
  end

  # A killed process lingers as a zombie until its parent reaps it, so poll for a moment.
  def gone?(pid)
    20.times do
      Process.kill(0, pid)
      sleep 0.05
    end
    false
  rescue Errno::ESRCH
    true
  end

  def stop(pid)
    Process.kill('KILL', pid)
    Process.wait(pid)
  rescue Errno::ESRCH, Errno::ECHILD
    nil
  end

  def clock = Process.clock_gettime(Process::CLOCK_MONOTONIC)
end
