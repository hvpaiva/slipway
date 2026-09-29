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

    # Credentials, a passphrase or a host key confirmation were missing or refused, and network
    # commands never prompt for them.
    class AuthRequired < Error
      def initialize(path) = super(path, 'authentication required and prompts are disabled')

      def hint = "Run 'git -C #{Shellwords.escape(path)} fetch' once in a terminal to see what git needs."
    end

    class LocalUpstream < Error
      def initialize(path) = super(path, 'the current branch tracks a local branch, not a remote one')
    end

    # Git refuses a transport that GIT_ALLOW_PROTOCOL, built from the "protocols" setting, does not list.
    class ProtocolNotAllowed < Error
      # The transports the "protocols" setting refuses to list, so no hint suggests adding one.
      UNSAFE = %w[ext fd].freeze

      attr_reader :protocol

      # +source+ says where the transports are listed, worded for the hint.
      def initialize(path, protocol:, source:)
        @protocol = protocol
        @source = source
        super(path, "transport '#{protocol}' not allowed")
      end

      def hint
        "Add #{protocol} to #{@source} to allow it." unless UNSAFE.include?(protocol)
      end
    end
  end
end
