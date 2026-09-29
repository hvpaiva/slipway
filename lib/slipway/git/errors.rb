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
      DETAIL = 'git did not finish within %<seconds>g %<unit>s'

      def initialize(path, seconds: Runner::DEFAULT_TIMEOUT)
        unit = seconds == 1 ? 'second' : 'seconds'
        super(path, format(self.class::DETAIL, seconds:, unit:))
      end
    end

    # Git stopped partway through writing the working tree leaves the branch and the index where
    # they were, but keeps the files it had written, and they then show as changes.
    class WriteTimeout < Timeout
      DETAIL = "#{Timeout::DETAIL}; the files it had written stay in the working tree".freeze

      def hint = "Run 'git -C #{Shellwords.escape(path)} status' to see them."
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
      def command = "git config --global --add safe.directory #{Shellwords.escape(path)}"

      def hint = "Run '#{command}' to trust it."
    end

    # Credentials, a passphrase or a host key confirmation were missing or refused, and network
    # commands never prompt for them.
    class AuthRequired < Error
      def initialize(path, detail = 'authentication required and prompts are disabled') = super

      def hint = "Run 'git -C #{Shellwords.escape(path)} fetch' once in a terminal to see what git needs."
    end

    class LocalUpstream < Error
      def initialize(path) = super(path, 'the current branch tracks a local branch, not a remote one')
    end

    # The branch was left where it was. +reason+ names why in one word: a state in which a
    # fast-forward is never attempted or, for the subclasses, git's own refusal.
    class Blocked < Error
      attr_reader :reason

      def initialize(path, reason, detail)
        @reason = reason
        super(path, detail)
      end
    end

    # Git cannot tell a running process from one that died holding the lock, and neither can
    # slipway, so the lock stays.
    class Busy < Blocked
      def initialize(path, lock = 'index.lock')
        super(path, 'Busy', "another git process holds #{lock}, or one left it behind")
      end
    end

    class WouldOverwrite < Blocked
      def initialize(path) = super(path, 'WouldOverwrite', 'the incoming commits would overwrite untracked files')
    end

    class WouldLoseChanges < Blocked
      def initialize(path) = super(path, 'WouldLoseChanges', 'the incoming commits would overwrite local changes')
    end

    class NotFastForward < Blocked
      def initialize(path) = super(path, 'NotFastForward', 'the branch cannot be fast-forwarded')
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
