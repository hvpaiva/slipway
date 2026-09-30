# frozen_string_literal: true

require_relative 'fetch_result'
require_relative 'fast_forward'
require_relative 'move_back'

module Slipway
  module Git
    # +calls+ lists every question asked and every move made, as [name, path] or
    # [name, path, options], so a test can tell which repositories a command reached and what it
    # changed.
    class Fake
      Entry = Data.define(:status, :commit, :remote, :remotes, :operation, :fetch, :fetched_at, :fast_forward,
                          :distance, :reflog, :between, :roll_back)

      NOTHING_FETCHED = FetchResult.new(updates: [].freeze)

      def initialize
        @entries = {}
        @failures = {}
        @calls = []
        @lock = Mutex.new
      end

      # +fetch+ is the FetchResult a fetch returns, and +fast_forward+ the FastForward the next
      # move returns (nil moves nothing and names +commit+); either may instead be an error, raised
      # the way fail raises it. +remotes+ names the configured remotes, origin alone when +remote+
      # is its URL. +operation+ is what in_progress answers, and +distance+ what distance answers
      # for any revision (nil: no such commit). +reflog+ is what reflog answers for any branch,
      # +between+ what commits_between answers for any two commits, and +roll_back+ the MoveBack
      # the next roll back returns, or the error it raises.
      def add(path, status:, commit: nil, remote: nil, remotes: nil, operation: nil, fetch: NOTHING_FETCHED,
              fetched_at: nil, fast_forward: nil, distance: nil, reflog: [], between: nil, roll_back: nil)
        key = File.expand_path(path)
        @failures.delete(key)
        remotes ||= remote ? ['origin'] : []
        @entries[key] = Entry.new(status:, commit:, remote:, remotes:, operation:, fetch:, fetched_at:, fast_forward:,
                                  distance:, reflog:, between:, roll_back:)
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

      def in_progress(path) = entry(:in_progress, path).operation

      def distance(path, revision, tracking: false) = entry(:distance, path, revision:, tracking:).distance

      def reflog(path, branch) = entry(:reflog, path, branch:).reflog

      def commits_between(path, from, to) = entry(:commits_between, path, from:, to:).between

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

      # A move happens once, as on a real branch: the status and the last commit then show the new
      # head, that many commits fewer behind, and the next fast-forward moves nothing.
      def fast_forward(path, onto: Repository::UPSTREAM, reflog_action: Repository::REFLOG_ACTION)
        move(:fast_forward, path, FastForward, 1, onto:, reflog_action:)
      end

      # A move back happens once too, and leaves the branch that many commits further behind.
      def roll_back(path, to:, reflog_action: Repository::ROLLBACK_ACTION)
        move(:roll_back, path, MoveBack, -1, to:, reflog_action:)
      end

      private

      def entry(name, path, **) = @lock.synchronize { lookup(name, File.expand_path(path), **) }

      # A path nobody registered is a path that does not exist, as for the real Repository.
      # Called with the lock held.
      def lookup(name, key, **options)
        @calls << (options.empty? ? [name, key] : [name, key, options])
        raise failure(key, @failures[key]) if @failures.key?(key)

        @entries.fetch(key) { raise MissingPath, key }
      end

      def move(name, path, type, direction, **)
        key = File.expand_path(path)
        @lock.synchronize do
          current = lookup(name, key, **)
          move = current.public_send(name) || still(key, current, type)
          raise failure(key, move) unless move.is_a?(type)

          @entries[key] = moved(current, move, direction * move.count).with(name => nil) if move.moved?
          move
        end
      end

      # A real move names HEAD in full, as only the last commit does.
      def still(key, entry, type)
        head = entry.commit&.sha
        raise ArgumentError, "#{key}: a move that goes nowhere names the last commit; add one" unless head

        type.new(from: head, to: head, count: 0)
      end

      def moved(entry, move, gained)
        status = entry.status
        behind = [status.behind.to_i - gained, 0].max
        short = move.to[0, Porcelain::ABBREVIATION]
        entry.with(status: status.with(head: short, behind:), commit: entry.commit&.with(sha: move.to, short:))
      end

      def failure(key, error)
        error.is_a?(Class) ? error.new(key) : error
      end
    end
  end
end
