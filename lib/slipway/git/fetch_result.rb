# frozen_string_literal: true

module Slipway
  module Git
    # +updates+ holds [ref, old, new] for each ref the fetch moved, or is nil when git fetched
    # without listing them (git before 2.41). The old id of a new ref and the new id of a pruned
    # one are git's all-zero id.
    FetchResult = Data.define(:updates) do
      # Parses `git fetch --porcelain`: one "FLAG OLD NEW REF" line per updated ref, and nothing
      # when the fetch brought nothing new. A fetched ref that no refspec maps (a single-branch
      # clone on a branch that tracks another one, a remote without a fetch refspec) is reported
      # as FETCH_HEAD on every fetch, though no ref moved.
      def self.parse(text)
        updates = text.each_line(chomp: true).filter_map do |line|
          old_id, new_id, ref = line[2..].split(' ', 3)
          [ref, old_id, new_id].freeze unless ref == Repository::FETCH_HEAD
        end
        new(updates: updates.freeze)
      end
    end
  end
end
