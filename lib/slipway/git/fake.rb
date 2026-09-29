# frozen_string_literal: true

module Slipway
  module Git
    # Stands in for Repository in tests: answers from a Hash keyed by expanded path and raises
    # whatever error a path was configured to fail with.
    class Fake
      # Canned answers for one path.
      Entry = Data.define(:status, :commit, :remote)

      def initialize
        @entries = {}
        @failures = {}
      end

      # Registers the answers for +path+; a later call replaces them and clears any failure.
      def add(path, status:, commit: nil, remote: nil)
        key = File.expand_path(path)
        @failures.delete(key)
        @entries[key] = Entry.new(status:, commit:, remote:)
        self
      end

      # Makes every query about +path+ raise +error+, an exception instance or a Git error
      # class that takes the path as its only argument.
      def fail(path, error)
        key = File.expand_path(path)
        @entries.delete(key)
        @failures[key] = error
        self
      end

      def status(path) = entry(path).status

      def last_commit(path) = entry(path).commit

      def remote_url(path) = entry(path).remote

      private

      # A path nobody registered is a path that does not exist, as for the real Repository.
      def entry(path)
        key = File.expand_path(path)
        raise failure(key, @failures[key]) if @failures.key?(key)

        @entries.fetch(key) { raise MissingPath, key }
      end

      def failure(key, error)
        error.is_a?(Class) ? error.new(key) : error
      end
    end
  end
end
