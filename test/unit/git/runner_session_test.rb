# frozen_string_literal: true

require 'test_helper'
require 'slipway/git'
require 'tmpdir'

# A helper that starts its own session escapes the group kill and can hold git's pipes for as
# long as it runs.
class GitRunnerSessionTest < Minitest::Test
  include GitFixtures

  def setup
    @root = Dir.mktmpdir('slipway-runner-')
    @saved = replace_env(hermetic_env(@root))
    @helper = File.join(@root, 'helper')
  end

  def teardown
    Process.kill('KILL', Integer(File.read(@helper))) if File.exist?(@helper)
  rescue Errno::ESRCH
    nil
  ensure
    restore_env(@saved)
    FileUtils.remove_entry(@root)
  end

  def test_the_deadline_holds_when_a_helper_outside_the_group_keeps_the_output_open
    with_a_session_helper('exec sleep 60') do
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      assert_raises(Slipway::Git::Timeout) { Slipway::Git::Runner.new.run(@root, 'fetch', timeout: 1) }

      assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 5
      assert_path_exists @helper, 'the helper never left the group'
    end
  end

  def test_an_interrupt_stops_the_readers_quietly_while_a_helper_outside_the_group_keeps_the_output_open
    before = Thread.list

    with_a_session_helper('exit 0') do
      _, err = capture_io { interrupt_once_the_helper_runs(before) }

      assert_empty err
    end
  end

  private

  # Under bundle exec the helper would load bundler, whose gemspec runs git: this fake again.
  def with_a_session_helper(git_tail, &)
    bin = fake_git(@root, <<~SH)
      "#{RbConfig.ruby}" --disable-gems -e 'Process.setsid; File.write(ARGV[0], Process.pid); sleep 30' #{@helper} &
      #{git_tail}
    SH
    with_env('PATH' => "#{bin}:#{ENV.fetch('PATH')}", 'RUBYOPT' => nil, &)
  end

  def interrupt_once_the_helper_runs(before)
    running = Thread.new { Slipway::Git::Runner.new.run(@root, 'status') }
    running.report_on_exception = false
    sleep 0.05 until File.exist?(@helper)
    Thread.pass until running.stop?
    running.raise(Interrupt)
    assert_raises(Interrupt, 'the run waited for a pipe the helper holds') { running.join(5) }
    Thread.pass until (Thread.list - before).empty?
  end
end
