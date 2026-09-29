# frozen_string_literal: true

require 'json'
require 'psych'

module Slipway
  module Output
    # Emits resources as JSON or YAML in kubectl's shape: one object alone, or a List wrapping
    # many. Callers pass plain Hashes with string keys and strings for timestamps, because the
    # YAML dump admits only the core scalar types.
    module Serializer
      FORMATS = %w[table wide json yaml name].freeze
      STRUCTURED = %w[json yaml].freeze
      LIST_KIND = 'List'

      # Renders +items+ in +format+ (json or yaml). With +single+ the first item is emitted
      # on its own; otherwise every item goes under a List.
      def self.render(format, items, single:)
        document = single ? items.first : { 'kind' => LIST_KIND, 'items' => items }
        case format
        when 'json' then "#{JSON.pretty_generate(document)}\n"
        when 'yaml' then Psych.safe_dump(document, line_width: -1).delete_prefix("---\n")
        else raise ArgumentError, unknown_format(format)
        end
      end

      def self.unknown_format(format)
        "unknown structured format #{format.inspect} (known formats: #{STRUCTURED.join(', ')})"
      end

      private_class_method :unknown_format
    end
  end
end
