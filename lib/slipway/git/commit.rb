# frozen_string_literal: true

module Slipway
  module Git
    Commit = Data.define(:sha, :short, :time, :author, :email, :subject) do
      # One record in the field order of Repository::LOG_ARGS.
      def self.parse(text)
        sha, short, epoch, author, email, subject = text.chomp("\0").split("\0", 6)
        new(sha:, short:, time: Time.at(Integer(epoch)).utc, author:, email:, subject: subject.to_s)
      end
    end
  end
end
