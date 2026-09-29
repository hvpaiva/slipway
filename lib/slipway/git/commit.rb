# frozen_string_literal: true

module Slipway
  module Git
    # The commit HEAD points at, with its time in UTC.
    Commit = Data.define(:sha, :short, :time, :author, :email, :subject) do
      # Parses one `git log -1 -z` record whose fields are the full and abbreviated ids, the
      # committer epoch, the author name and email and the subject, NUL separated.
      def self.parse(text)
        sha, short, epoch, author, email, subject = text.chomp("\0").split("\0", 6)
        new(sha:, short:, time: Time.at(Integer(epoch)).utc, author:, email:, subject: subject.to_s)
      end
    end
  end
end
