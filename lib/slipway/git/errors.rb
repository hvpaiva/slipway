# frozen_string_literal: true

require 'shellwords'

module Slipway
  module Git
    # Base class for every git failure; the message starts with the path it refers to.
    class Error < Slipway::Error
      attr_reader :path

      def initialize(path, detail = 'git command failed')
        @path = path
        super("#{path}: #{detail}")
      end
    end

    # The git executable could not be started at all.
    class NotInstalled < Error
      def initialize(path, binary: Runner::DEFAULT_BINARY)
        super(path, "git executable #{binary.inspect} not found on PATH")
      end
    end

    # The git process was killed because it ran past the deadline.
    class Timeout < Error
      def initialize(path, seconds: Runner::DEFAULT_TIMEOUT)
        super(path, format('git did not finish within %g seconds', seconds))
      end
    end

    # The registered path is not a directory on this machine.
    class MissingPath < Error
      def initialize(path) = super(path, 'no such directory')
    end

    # The directory exists but no repository contains it.
    class NotARepository < Error
      def initialize(path) = super(path, 'not a git repository')
    end

    # Git refused the repository because another user owns it (safe.directory).
    class UnsafeRepository < Error
      def initialize(path) = super(path, 'repository has dubious ownership')

      # Git's own remedy, so the user can decide whether to trust the directory.
      def hint = "Run 'git config --global --add safe.directory #{Shellwords.escape(path)}' to trust it."
    end
  end
end
