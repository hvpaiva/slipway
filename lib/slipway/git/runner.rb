# frozen_string_literal: true

require 'open3'

module Slipway
  module Git
    # The one place that spawns git: runs `git -C <path> ...` with a hardened environment,
    # kills the whole process group when the deadline passes, and returns UTF-8 output.
    class Runner
      # Exit status plus both streams of one finished git process.
      Result = Data.define(:status, :out, :err) do
        def success? = status.zero?
      end

      DEFAULT_BINARY = 'git'
      DEFAULT_TIMEOUT = 10.0
      # Shell convention for a process ended by a signal: 128 plus the signal number.
      SIGNAL_STATUS_BASE = 128

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
        'GIT_ALTERNATE_OBJECT_DIRECTORIES' => nil,
        'GIT_CEILING_DIRECTORIES' => nil
      }.freeze

      attr_reader :binary, :timeout

      def initialize(binary: DEFAULT_BINARY, timeout: DEFAULT_TIMEOUT)
        @binary = binary
        @timeout = timeout
      end

      # Runs `git -C path args...` and returns a Result whatever git's exit status is. Raises
      # NotInstalled when the binary cannot be started and Timeout when the deadline passes.
      def run(path, *)
        directory = File.expand_path(path)
        Open3.popen3(ENVIRONMENT, @binary, '-C', directory, *, pgroup: true) do |stdin, stdout, stderr, wait|
          stdin.close
          readers = [stdout, stderr].map { reader(it) }
          terminate(wait, readers, directory) unless wait.join(@timeout)
          out, err = readers.map { scrub(it.value) }
          Result.new(status: exit_status(wait.value), out:, err:)
        end
      rescue Errno::ENOENT
        raise NotInstalled.new(directory, binary: @binary)
      end

      private

      # Drains one pipe on its own thread so a chatty command cannot deadlock on a full buffer.
      def reader(io)
        io.binmode
        Thread.new { io.read }
      end

      # Kills the process group so helpers git spawned die with it, then reports the deadline.
      # The readers are joined after the kill so closing the pipes cannot interrupt them.
      def terminate(wait, readers, directory)
        begin
          Process.kill('KILL', -wait.pid)
        rescue Errno::ESRCH
          nil
        end
        wait.join
        readers.each(&:join)
        raise Timeout.new(directory, seconds: @timeout)
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
