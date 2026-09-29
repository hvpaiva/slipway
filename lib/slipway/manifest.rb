# frozen_string_literal: true

require 'psych'
require 'time'
require_relative 'cli/errors'
require_relative 'names'
require_relative 'labels'
require_relative 'resources'

module Slipway
  # Reads and writes the YAML form of a Project or Group.
  module Manifest
    # A document that does not describe a valid resource; the message starts with where it came from.
    class Invalid < Error
      attr_reader :source, :problem

      def initialize(source, problem)
        @source = source
        @problem = problem
        super("#{source}: #{problem}")
      end
    end

    # Turns one string-keyed document into a resource, reporting the first problem it finds.
    class Reader
      FIELDS = {
        'Project' => { root: %w[kind metadata spec], metadata: %w[name group labels creationTimestamp],
                       spec: %w[path description] },
        'Group' => { root: %w[kind metadata spec], metadata: %w[name labels creationTimestamp],
                     spec: %w[description] }
      }.freeze
      TIMESTAMP = /\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})\z/

      def initialize(document, source, default_group)
        @document = document
        @source = source
        @default_group = default_group
      end

      def resource
        invalid('document is not a mapping') unless @document.is_a?(Hash)
        fields = FIELDS.fetch(kind)
        reject_unknown(@document, fields[:root], nil)
        @metadata = mapping('metadata', fields[:metadata])
        @spec = mapping('spec', fields[:spec])
        kind == 'Project' ? project : group
      end

      private

      def kind
        case @document['kind']
        in 'Project' | 'Group' => kind then kind
        in nil then invalid('"kind" is required')
        in String => other then invalid("\"kind\" must be Project or Group, not #{other.inspect}")
        else invalid('"kind" must be a string')
        end
      end

      def project
        Project.new(name:, group: group_name, labels:, created_at:,
                    path: string(@spec, 'spec', 'path', required: true),
                    description: string(@spec, 'spec', 'description'))
      end

      def group
        Group.new(name:, labels:, created_at:, description: string(@spec, 'spec', 'description'))
      end

      def name
        checked do
          Names.validate!(string(@metadata, 'metadata', 'name', required: true), what: "#{kind.downcase} name")
        end
      end

      def group_name
        checked { Names.validate!(string(@metadata, 'metadata', 'group') || @default_group, what: 'group name') }
      end

      def labels
        case @metadata['labels']
        in nil then {}
        in Hash => labels then checked { Labels.validate!(string_pairs(labels)) }
        else invalid('"metadata.labels" must be a mapping')
        end
      end

      def string_pairs(labels)
        labels.each do |key, value|
          invalid('"metadata.labels" keys must be strings') unless key.is_a?(String)
          invalid("\"metadata.labels.#{key}\" must be a string") unless value.is_a?(String)
        end
      end

      def created_at
        case @metadata['creationTimestamp']
        in nil then nil
        in String => text if TIMESTAMP.match?(text) then time(text)
        else invalid('"metadata.creationTimestamp" must be an RFC 3339 timestamp')
        end
      end

      # Second precision, so the value read back equals the value written.
      def time(text)
        Time.iso8601(text).getutc.floor
      rescue ArgumentError
        invalid('"metadata.creationTimestamp" must be an RFC 3339 timestamp')
      end

      def mapping(key, allowed)
        case @document[key]
        in nil then {}
        in Hash => section then reject_unknown(section, allowed, key)
        else invalid("\"#{key}\" must be a mapping")
        end
      end

      def reject_unknown(section, allowed, prefix)
        section.each_key do |key|
          next if allowed.include?(key)

          invalid("unknown field #{[prefix, key].compact.join('.').inspect}")
        end
      end

      def string(section, prefix, key, required: false)
        case section[key]
        in String => value then value
        in nil if required then invalid("\"#{prefix}.#{key}\" is required")
        in nil then nil
        else invalid("\"#{prefix}.#{key}\" must be a string")
        end
      end

      # Name and label rules raise Slipway::Error; here they belong to the document.
      def checked
        yield
      rescue Invalid
        raise
      rescue Error => e
        invalid(e.message)
      end

      def invalid(problem)
        raise Invalid.new(@source, problem)
      end
    end

    private_constant :Reader

    # Builds a Project or Group from a string-keyed Hash; +default_group+ applies when metadata.group is absent.
    def self.parse(hash, source:, default_group: 'default') = Reader.new(hash, source, default_group).resource

    # Every mapping in a YAML stream; empty documents are skipped and anything else is Invalid.
    def self.load_documents(text, source:)
      Psych.safe_load_stream(text, filename: source).each_with_index.filter_map do |document, index|
        case document
        in nil then nil
        in Hash then document
        else raise Invalid.new(source, "document #{index + 1} is not a mapping")
        end
      end
    rescue Psych::SyntaxError => e
      raise Invalid.new(source, "#{e.problem} at line #{e.line}, column #{e.column}")
    rescue Psych::DisallowedClass, Psych::BadAlias => e
      raise Invalid.new(source, e.message)
    end

    # Parses YAML holding exactly one resource.
    def self.parse_yaml(text, source:, default_group: 'default')
      case load_documents(text, source:)
      in [document] then parse(document, source:, default_group:)
      in [] then raise Invalid.new(source, 'expected one document, found none')
      in documents then raise Invalid.new(source, "expected one document, found #{documents.size}")
      end
    end

    # The YAML text of a resource, without the leading document marker, the way kubectl prints objects.
    def self.dump(resource) = Psych.safe_dump(resource.to_manifest, line_width: -1).delete_prefix("---\n")
  end
end
