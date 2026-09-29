# frozen_string_literal: true

require_relative '../yaml'

module Slipway
  module Output
    # Emits resources as JSON or YAML in kubectl's shape: one object alone, or a List wrapping
    # many. Callers pass plain Hashes with string keys and strings for timestamps, because the
    # YAML dump admits only the core scalar types.
    module Serializer
      STRUCTURED = %w[json yaml].freeze
      LIST_KIND = 'List'

      # Renders +items+ in +format+ (json or yaml). With +single+ the first item is emitted
      # on its own; otherwise every item goes under a List.
      def self.render(format, items, single:)
        document = single ? items.first : { 'kind' => LIST_KIND, 'items' => items }
        case format
        when 'json' then json(document)
        when 'yaml' then Yaml.dump(document)
        else raise ArgumentError, unknown_format(format)
        end
      end

      # The json library is loaded on first use; most runs print a table and never need it.
      def self.json(document)
        require 'json'
        "#{JSON.pretty_generate(document)}\n"
      end

      def self.unknown_format(format)
        "unknown structured format #{format.inspect} (known formats: #{STRUCTURED.join(', ')})"
      end

      private_class_method :json, :unknown_format
    end
  end
end
