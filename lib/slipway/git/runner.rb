# frozen_string_literal: true

module Slipway
  module Git
    # The one place that spawns git.
    class Runner
      Result = Data.define(:status, :out, :err) do
        def success? = status.zero?
      end

      DEFAULT_BINARY = 'git'
      DEFAULT_TIMEOUT = 10.0
      # Git deletes its lock files when TERM arrives, and KILL cannot be caught: a git killed
      # while it updates refs would leave locks that fail every later command that moves them.
      TERM_GRACE = 1.0
      # Shell convention for a process ended by a signal: 128 plus the signal number.
      SIGNAL_STATUS_BASE = 128
      CEILING_VARIABLE = 'GIT_CEILING_DIRECTORIES'
      PROTOCOL_VARIABLE = 'GIT_ALLOW_PROTOCOL'
      # Absolute, so no program named false earlier on PATH stands in for it; macOS has only
      # /usr/bin/false.
      FALSE_PROGRAMS = %w[/usr/bin/false /bin/false].freeze

      # LC_ALL=C keeps messages parseable; prompts and optional index writes are disabled; every
      # repository-selecting variable is unset so an inherited GIT_DIR cannot redirect a query.
      ENVIRONMENT = {
        'LC_ALL' => 'C',
        'LANGUAGE' => nil,
        'GIT_TERMINAL_PROMPT' => '0',
        'GIT_OPTIONAL_LOCKS' => '0',
        'GIT_PAGER' => 'cat',
        'GIT_DIR' => nil,
        'GIT_WORK_TREE' => nil,
        'GIT_INDEX_FILE' => nil,
        'GIT_NAMESPACE' => nil,
        'GIT_OBJECT_DIRECTORY' => nil,
        'GIT_ALTERNATE_OBJECT_DIRECTORIES' => nil
      }.freeze

      # A path that names no program still fails the prompt, which is all the askpass is for.
      def self.false_program(candidates = FALSE_PROGRAMS) = candidates.find { File.executable?(it) } || candidates.first

      FALSE_PROGRAM = false_program

      # Every credential or host key question is answered by false, so git and ssh fail at once
      # instead of waiting on a prompt nobody sees. SSH_ASKPASS_REQUIRE=force (OpenSSH 8.4 and
      # later) sends every ssh prompt to the askpass, with or without DISPLAY, so ssh never reads
      # /dev/tty.
      NETWORK_ENVIRONMENT = {
        'GIT_ASKPASS' => FALSE_PROGRAM,
        'SSH_ASKPASS' => FALSE_PROGRAM,
        'SSH_ASKPASS_REQUIRE' => 'force'
      }.freeze

      # No gc or maintenance started on the user's behalf, and no bundle download from a URL the
      # server advertises.
      NETWORK_CONFIG = %w[-c gc.auto=0 -c maintenance.auto=false -c transfer.bundleURI=false].freeze

      # GIT_ALLOW_PROTOCOL refuses every transport it does not list, including file and ext.
      def self.network_environment(protocols) = NETWORK_ENVIRONMENT.merge(PROTOCOL_VARIABLE => protocols.join(':'))

      attr_reader :binary, :timeout

      def initialize(binary: DEFAULT_BINARY, timeout: DEFAULT_TIMEOUT)
        @binary = binary
        @timeout = timeout
      end

      # Returns a Result whatever git's exit status is. Raises NotInstalled when the binary
      # cannot be started and Timeout when `timeout` seconds pass. `env` adds variables to the
      # child; it cannot change the ones ENVIRONMENT pins.
      # A git still running when the block unwinds for any other reason, such as an
      # interrupt, is killed with its process group instead of outliving the command.
      def run(path, *, timeout: @timeout, env: {})
        require 'open3'
        directory = File.expand_path(path)
        # Open3 spawns git before this block's ensure is armed, so an interrupt or a Thread#kill
        # (not an Exception, hence Object) landing in between would leave it running; both are
        # held until the block runs.
        Thread.handle_interrupt(Object => :never) do
          Open3.popen3(environment(directory, env), @binary, '-C', directory, *, pgroup: true) do |stdin, *pipes, wait|
            stdin.close
            readers = pipes.map { reader(it) }
            Thread.handle_interrupt(Object => :immediate) { collect(wait, readers, directory, timeout) }
          ensure
            reap(wait, Array(readers))
          end
        end
      rescue Errno::ENOENT
        raise NotInstalled.new(directory, binary: @binary)
      end

      private

      # A helper git started can hold a pipe open after git exits, so the deadline covers the
      # pipes too.
      def collect(wait, readers, directory, timeout)
        unless settled?([wait, *readers], timeout)
          stop(wait, readers)
          raise Timeout.new(directory, seconds: timeout)
        end
        out, err = readers.map { scrub(it.value) }
        Result.new(status: exit_status(wait.value), out:, err:)
      end

      # Discovery must not climb above the registered directory, or a subdirectory of some
      # other repository would report that repository's state. Git compares real paths, so
      # the ceiling is the real parent.
      def environment(directory, extra)
        extra.merge(ENVIRONMENT, CEILING_VARIABLE => File.dirname(realpath(directory)))
      end

      def realpath(directory)
        File.realpath(directory)
      rescue SystemCallError
        directory
      end

      # Drains one pipe on its own thread so a chatty command cannot deadlock on a full buffer.
      # A new thread inherits the interrupts run holds; the read lets them in again so stop can
      # kill it. Its result is only taken through value, which re-raises, so a reader whose pipe
      # is closed under it stays quiet instead of printing a thread trace.
      def reader(io)
        io.binmode
        Thread.new do
          Thread.current.report_on_exception = false
          Thread.handle_interrupt(Object => :immediate) { io.read }
        end
      end

      def settled?(threads, timeout)
        deadline = clock + timeout
        threads.all? { it.join([deadline - clock, 0].max) }
      end

      def clock = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      # This runs with interrupts held, and the thread Open3 waits for git on inherited that
      # mask, so neither another interrupt nor process exit can end them while git lives.
      def reap(wait, readers)
        stop(wait, readers) if wait.alive? || readers.any?(&:alive?)
      end

      # KILL follows as soon as git exits or the grace ends, so a helper that ignores TERM dies
      # even when git has already exited. The readers are stopped, not drained: a helper that left
      # the group can hold a pipe open forever.
      def stop(wait, readers)
        signal(wait, 'TERM')
        wait.join(TERM_GRACE)
        signal(wait, 'KILL')
        wait.join
        readers.each { it.kill.join }
      end

      # macOS answers EPERM, not ESRCH, when every process left in the group has exited but is
      # not yet reaped. git runs as this user, so either answer means nothing is left to signal,
      # and raising would replace the interrupt, kill or timeout that is ending the run.
      def signal(wait, name)
        Process.kill(name, -wait.pid)
      rescue Errno::ESRCH, Errno::EPERM
        nil
      end

      def exit_status(process)
        process.exitstatus || (SIGNAL_STATUS_BASE + process.termsig)
      end

      # Paths in git output are raw bytes; invalid sequences become U+FFFD so every consumer
      # gets a valid UTF-8 string.
      def scrub(bytes)
        bytes.force_encoding(Encoding::UTF_8).scrub
      end
    end
  end
end
