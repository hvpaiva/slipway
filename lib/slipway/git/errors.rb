# frozen_string_literal: true

require 'shellwords'
require_relative '../error'

module Slipway
  module Git
    class Error < Slipway::Error
      attr_reader :path

      def initialize(path, detail = 'git command failed')
        @path = path
        super("#{path}: #{detail}")
      end
    end

    class NotInstalled < Error
      def initialize(path, binary: Runner::DEFAULT_BINARY)
        super(path, "git executable #{binary.inspect} not found on PATH")
      end
    end

    class Timeout < Error
      def initialize(path, seconds: Runner::DEFAULT_TIMEOUT)
        unit = seconds == 1 ? 'second' : 'seconds'
        super(path, format('git did not finish within %<seconds>g %<unit>s', seconds:, unit:))
      end
    end

    class MissingPath < Error
      def initialize(path, detail = 'no such directory') = super
    end

    # A manifest has no directory to resolve a relative path against.
    class RelativePath < MissingPath
      def initialize(path) = super(path, 'relative path; register an absolute path or one starting with ~/')
    end

    class NotARepository < Error
      def initialize(path) = super(path, 'not a git repository')
    end

    # Git refuses a repository another user owns unless safe.directory lists it.
    class UnsafeRepository < Error
      def initialize(path) = super(path, 'repository has dubious ownership')

      # Git's own remedy, so the user can decide whether to trust the directory.
      def hint = "Run 'git config --global --add safe.directory #{Shellwords.escape(path)}' to trust it."
    end
  end
end
