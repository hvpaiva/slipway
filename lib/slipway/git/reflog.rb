# frozen_string_literal: true

module Slipway
  module Git
    # One move of a branch as its reflog records it: the commit the branch pointed at after the
    # move, when the move happened, and git's subject for it, such as "slipway sync: Fast-forward".
    ReflogEntry = Data.define(:sha, :time, :subject)

    module Reflog
      # A date format makes %gd name the time of each move; %ct would be the commit's own date,
      # the same for every move to one commit. log.showSignature would add gpg's lines.
      FORMAT = ['--date=unix', '--format=%H%x00%gd%x00%gs', '--no-show-signature'].freeze
      SELECTOR_TIME = /@\{(\d+)\}\z/
      FIELDS = 3

      # Parses `git reflog show -z` in FORMAT, newest entry first as git lists them.
      def self.parse(text)
        text.chomp("\0").split("\0", -1).each_slice(FIELDS).filter_map do |sha, selector, subject|
          time = selector.to_s[SELECTOR_TIME, 1]
          ReflogEntry.new(sha:, time: Time.at(Integer(time, 10)).utc, subject:) if time && subject
        end
      end
    end
  end
end
