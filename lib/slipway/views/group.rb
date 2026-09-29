# frozen_string_literal: true

require_relative '../output'

module Slipway
  module Views
    module Group
      # See Views::Project::FIELDS.
      FIELDS = { 'metadata.name' => '' }.freeze

      def self.headers(wide: false)
        columns = %w[NAME PROJECTS AGE]
        columns << 'DESCRIPTION' if wide
        columns
      end

      def self.row(group, count:, now:, wide: false)
        cells = [group.name, count.to_s, Output::Age.humanize(group.created_at, now)]
        cells << group.description if wide
        cells
      end

      def self.describe(group, count:, now:)
        [['Name', group.name], ['Labels', group.labels], ['Created', group.created_at],
         ['Age', Output::Age.humanize(group.created_at, now)], ['Description', group.description],
         ['Projects', count]]
      end

      def self.object(group, count:) = group.to_manifest.merge('status' => { 'projects' => count })
    end
  end
end
