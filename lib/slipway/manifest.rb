# frozen_string_literal: true

require 'psych'
require 'time'
require_relative 'error'
require_relative 'git/branch_name'
require_relative 'git/url'
require_relative 'names'
require_relative 'labels'
require_relative 'resources'
require_relative 'schema'
require_relative 'yaml'

module Slipway
  module Manifest
    class Invalid < Error
      attr_reader :source, :problem

      def initialize(source, problem)
        @source = source
        @problem = problem
        super("#{source}: #{problem}")
      end
    end

    # Turns one parsed document into a Project or a Group, or raises Invalid with the source and
    # the first field that breaks its rule. Which fields exist, which are required, their defaults
    # and the words of each refusal come from Schema, so a field Schema does not name is refused.
    # Every field that can reach git or a command slipway prints is checked here, so a resource
    # read from the store or applied from a file can be handed to Git::Repository as it is.
    class Reader
      TIMESTAMP = /\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})\z/
      # SHA-1 or SHA-256; an abbreviation can become ambiguous as the repository grows.
      REVISION = /\A(?:[0-9a-f]{40}|[0-9a-f]{64})\z/

      def initialize(document, source, default_group)
        @document = document
        @source = source
        @default_group = default_group
      end

      def resource
        invalid('document is not a mapping') unless @document.is_a?(Hash)
        @schema = Schema::KINDS.fetch(kind)
        reject_unknown(@document, @schema, nil)
        @metadata = mapping('metadata')
        @spec = mapping('spec')
        kind == 'Project' ? project : group
      end

      private

      def kind
        case @document['kind']
        in String => kind if Schema::KINDS.key?(kind) then kind
        in nil then required('kind')
        in String => other then invalid("\"kind\" must be #{Schema::KINDS.keys.join(' or ')}, not #{other.inspect}")
        else mistyped('kind', Schema::STRING)
        end
      end

      def project
        Project.new(name:, group: group_name, labels:, created_at:, path:, description:, remote:, branch:, revision:,
                    sync_policy:, paused:)
      end

      def group = Group.new(name:, labels:, created_at:, description:)

      def name
        checked { Names.validate!(string(@metadata, 'metadata', 'name'), what: "#{kind.downcase} name") }
      end

      def group_name
        checked { Names.validate!(string(@metadata, 'metadata', 'group') || @default_group, what: 'group name') }
      end

      # An empty path would be resolved against whatever directory the reader happens to be in.
      def path
        value = string(@spec, 'spec', 'path')
        broken('spec', 'path') if value.strip.empty?
        value
      end

      def description = string(@spec, 'spec', 'description')

      def remote
        url = string(@spec, 'spec', 'remote')
        url && checked { Git::Url.validate!(url, field: '"spec.remote"') }
      end

      def branch
        name = string(@spec, 'spec', 'branch')
        name && checked { Git::BranchName.validate!(name) }
      end

      def revision
        case @spec['revision']
        in nil then nil
        in String => sha if REVISION.match?(sha) then sha
        else broken('spec', 'revision')
        end
      end

      def sync_policy
        field = @schema.dig('spec', 'syncPolicy')
        case @spec['syncPolicy']
        in nil then field.default
        in String => policy if field.enum.include?(policy) then policy
        in String => other then invalid("\"spec.syncPolicy\" #{field.rule}, not #{other.inspect}")
        else mistyped('spec.syncPolicy', Schema::STRING)
        end
      end

      def paused
        case @spec['paused']
        in nil then @schema.dig('spec', 'paused').default
        in true | false => paused then paused
        else mistyped('spec.paused', Schema::BOOLEAN)
        end
      end

      def labels
        case @metadata['labels']
        in nil then {}
        in Hash => labels then checked { Labels.validate!(string_pairs(labels)) }
        else mistyped('metadata.labels', Schema::LABEL_MAP)
        end
      end

      def string_pairs(labels)
        labels.each do |key, value|
          invalid('"metadata.labels" keys must be strings') unless key.is_a?(String)
          mistyped("metadata.labels.#{key}", Schema::STRING) unless value.is_a?(String)
        end
      end

      def created_at
        case @metadata['creationTimestamp']
        in nil then nil
        in String => text if TIMESTAMP.match?(text) then time(text)
        else broken('metadata', 'creationTimestamp')
        end
      end

      # Second precision, so the value read back equals the value written.
      def time(text)
        Time.iso8601(text).getutc.floor
      rescue ArgumentError
        broken('metadata', 'creationTimestamp')
      end

      def mapping(key)
        case @document[key]
        in nil then {}
        in Hash => section then reject_unknown(section, @schema.field(key), key)
        else mistyped(key, Schema::OBJECT)
        end
      end

      def reject_unknown(section, schema, prefix)
        section.each_key do |key|
          next if schema.field(key)

          invalid("unknown field #{[prefix, key].compact.join('.').inspect}")
        end
      end

      def string(section, prefix, key)
        case section[key]
        in String => value then value
        in nil if @schema.dig(prefix, key).required then required("#{prefix}.#{key}")
        in nil then nil
        else mistyped("#{prefix}.#{key}", Schema::STRING)
        end
      end

      def checked
        yield
      rescue Names::Invalid, Labels::Invalid, Git::Url::Invalid, Git::BranchName::Invalid => e
        invalid(e.message)
      end

      def required(path) = invalid("\"#{path}\" is required")

      def mistyped(path, type) = invalid("\"#{path}\" must be #{Schema::NOUNS.fetch(type)}")

      # For the fields whose rule this class checks itself rather than a module such as Names.
      def broken(prefix, key) = invalid("\"#{prefix}.#{key}\" #{@schema.dig(prefix, key).rule}")

      def invalid(problem)
        raise Invalid.new(@source, problem)
      end
    end

    private_constant :Reader

    LIST_KIND = 'List'
    LIST_FIELDS = %w[kind items].freeze

    # `hash` must have string keys.
    def self.parse(hash, source:, default_group: 'default') = Reader.new(hash, source, default_group).resource

    def self.load_documents(text, source:)
      documents(text, source).each_with_index.filter_map do |document, index|
        case document
        in nil then nil
        in Hash then document
        else raise Invalid.new(source, "document #{index + 1} is not a mapping")
        end
      end
    rescue Psych::SyntaxError => e
      raise Invalid.new(source, "#{e.problem} at line #{e.line}, column #{e.column}")
    rescue Psych::DisallowedClass => e
      raise Invalid.new(source, disallowed(e))
    rescue Psych::BadAlias => e
      raise Invalid.new(source, e.message)
    end

    # kubectl prints several objects as one List and applies such a List back item by item, so
    # each item stands for a document of its own.
    def self.load_objects(text, source:)
      load_documents(text, source:).flat_map { it['kind'] == LIST_KIND ? list_items(it, source) : [it] }
    end

    def self.list_items(list, source)
      unknown = list.keys - LIST_FIELDS
      raise Invalid.new(source, "unknown field #{unknown.first.inspect} in a List") unless unknown.empty?

      case list['items']
      in nil then []
      in Array => items if items.all?(Hash) then items
      else raise Invalid.new(source, '"items" of a List must be a sequence of mappings')
      end
    end
    private_class_method :list_items

    def self.parse_yaml(text, source:, default_group: 'default')
      case load_documents(text, source:)
      in [document] then parse(document, source:, default_group:)
      in [] then raise Invalid.new(source, 'expected one document, found none')
      in documents then raise Invalid.new(source, "expected one document, found #{documents.size}")
      end
    end

    # Psych.safe_load_stream only exists from psych 5.3 and the gem supports Ruby 3.4, so the
    # stream is parsed first and every document re-emitted alone for Psych.safe_load.
    def self.documents(text, source)
      Psych.parse_stream(text, filename: source).children.map do |document|
        stream = Psych::Nodes::Stream.new
        stream.children << document
        Psych.safe_load(stream.to_yaml, filename: source)
      end
    end
    private_class_method :documents

    # YAML types an unquoted 2026-09-29T00:12:33Z as a Time, which the safe loader refuses.
    def self.disallowed(error)
      klass = error.message.delete_prefix('Tried to load unspecified class: ')
      "#{klass} values are not accepted; timestamps, dates and symbols must be quoted strings"
    end
    private_class_method :disallowed

    def self.dump(resource) = Yaml.dump(resource.to_manifest)
  end
end
