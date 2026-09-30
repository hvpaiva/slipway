# frozen_string_literal: true

require_relative 'fetch_result'

module Slipway
  module Git
    # +calls+ lists every question asked, as [name, path] or [:fetch, path, { prune: }], so a test
    # can tell which repositories a command reached.
    class Fake
      Entry = Data.define(:status, :commit, :remote, :remotes, :fetch, :fetched_at)

      NOTHING_FETCHED = FetchResult.new(updates: [].freeze)

      def initialize
        @entries = {}
        @failures = {}
        @calls = []
        @lock = Mutex.new
      end

      # +fetch+ is the FetchResult a fetch returns, or an error raised the way fail raises it.
      # +remotes+ names the configured remotes, origin alone when +remote+ is its URL.
      def add(path, status:, commit: nil, remote: nil, remotes: nil, fetch: NOTHING_FETCHED, fetched_at: nil)
        key = File.expand_path(path)
        @failures.delete(key)
        remotes ||= remote ? ['origin'] : []
        @entries[key] = Entry.new(status:, commit:, remote:, remotes:, fetch:, fetched_at:)
        self
      end

      # +error+ is an exception instance or a Git error class that takes the path as its only
      # argument.
      def fail(path, error)
        key = File.expand_path(path)
        @entries.delete(key)
        @failures[key] = error
        self
      end

      def calls = @lock.synchronize { @calls.dup }

      def status(path) = entry(:status, path).status

      def last_commit(path) = entry(:last_commit, path).commit

      def remote_url(path) = entry(:remote_url, path).remote

      def fetch(path, prune:)
        outcome = entry(:fetch, path, prune:).fetch
        raise failure(File.expand_path(path), outcome) unless outcome.is_a?(FetchResult)

        outcome
      end

      # Read from the canned fetch, since the real fetch raises LocalUpstream exactly when this holds.
      def local_upstream?(path)
        key = File.expand_path(path)
        failure(key, entry(:local_upstream?, key).fetch).is_a?(LocalUpstream)
      end

      # Git takes the branch's remote, which an upstream implies, else the only remote, else origin.
      def default_remote?(path)
        answer = entry(:default_remote?, path)
        [answer.status.upstream, answer.remote].any? || answer.remotes.size == 1
      end

      def fetched_at(path) = entry(:fetched_at, path).fetched_at

      # Each path is a repository of its own.
      def common_dir(path) = File.expand_path(path)

      private

      # A path nobody registered is a path that does not exist, as for the real Repository.
      def entry(name, path, **options)
        key = File.expand_path(path)
        call = options.empty? ? [name, key] : [name, key, options]
        @lock.synchronize { @calls << call }
        raise failure(key, @failures[key]) if @failures.key?(key)

        @entries.fetch(key) { raise MissingPath, key }
      end

      def failure(key, error)
        error.is_a?(Class) ? error.new(key) : error
      end
    end
  end
end
