# frozen_string_literal: true

require 'shellwords'
require_relative 'error'

module Slipway
  # Opens text in the user's editor and returns what was saved.
  class Editor
    # Raised when the editor cannot be started, exits unsuccessfully or leaves no file behind;
    # exits with status 1.
    class Failed < Slipway::Error; end

    VARIABLE = 'SLIPWAY_EDITOR'
    FALLBACK_VARIABLES = %w[VISUAL EDITOR].freeze
    DEFAULT = 'vi'
    TMPDIR_PREFIX = 'slipway-edit-'

    # +preferred+ is the config file's editor, consulted after SLIPWAY_EDITOR and before VISUAL.
    def initialize(env:, preferred: nil)
      @env = env
      @preferred = preferred
    end

    # The editor as an argv Array, so `code --wait` and quoted paths work without a shell.
    def command
      Shellwords.split(command_line)
    rescue ArgumentError => e
      raise Failed, "editor #{command_line.inspect} is not a valid command line: #{e.message}"
    end

    # Writes +text+ to a fresh temporary directory as +filename+, runs the editor on it and
    # returns the file's content afterwards. The directory is removed on every path out.
    def edit(text, filename: 'resource.yaml')
      require 'tmpdir'
      Dir.mktmpdir(TMPDIR_PREFIX) do |dir|
        path = File.join(dir, filename)
        File.write(path, text)
        run(command, path)
        read_back(path, filename)
      end
    end

    private

    def command_line
      [@env[VARIABLE], @preferred, *FALLBACK_VARIABLES.map { @env[it] }].find { present?(it) } || DEFAULT
    end

    def present?(value) = !value.nil? && !value.strip.empty?

    def run(argv, path)
      started = system(*argv, path)
      return if started

      program = argv.first.inspect
      raise Failed, "editor #{program} not found" if started.nil?

      raise Failed, "editor #{program} #{describe(Process.last_status)}"
    end

    def describe(status)
      return "exited with status #{status.exitstatus}" if status.exited?

      "was killed by signal #{status.termsig}"
    end

    # An editor may delete or replace the file instead of saving over it.
    def read_back(path, filename)
      File.read(path)
    rescue Errno::ENOENT
      raise Failed, "editor removed #{filename}; edit cancelled"
    rescue SystemCallError => e
      raise Failed.from_system_call(e, path)
    end
  end
end
