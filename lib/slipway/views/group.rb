# frozen_string_literal: true

require_relative '../output'

module Slipway
  module Views
    # The table, describe and object forms of a group, with its project count.
    module Group
      module_function

      # Column titles; wide adds the description.
      def headers(wide: false)
        columns = %w[NAME PROJECTS AGE]
        columns << 'DESCRIPTION' if wide
        columns
      end

      # One table row for +group+ holding +count+ projects.
      def row(group, count:, now:, wide: false)
        cells = [group.name, count.to_s, Output::Age.humanize(group.created_at, now)]
        cells << group.description if wide
        cells
      end

      # The entries `describe` prints for a group.
      def describe(group, count:, now:)
        [['Name', group.name], ['Labels', group.labels], ['Created', group.created_at],
         ['Age', Output::Age.humanize(group.created_at, now)], ['Description', group.description],
         ['Projects', count]]
      end

      # The manifest plus the project count under status, for json and yaml.
      def object(group, count:) = group.to_manifest.merge('status' => { 'projects' => count })
    end
  end
end
