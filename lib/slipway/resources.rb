# frozen_string_literal: true

require_relative 'cli/errors'

module Slipway
  # A registered git repository: the fields of a manifest of kind Project.
  Project = Data.define(:name, :group, :labels, :created_at, :path, :description) do
    def initialize(name:, path:, group: 'default', labels: {}, created_at: nil, description: nil)
      super
    end

    def kind = 'Project'

    # The manifest Hash with string keys, in the order it is written to disk.
    def to_manifest
      metadata = { 'name' => name, 'group' => group, 'labels' => labels.sort.to_h,
                   'creationTimestamp' => Resources.timestamp(created_at) }.compact
      { 'kind' => kind, 'metadata' => metadata, 'spec' => { 'path' => path, 'description' => description }.compact }
    end

    def with_labels(labels) = with(labels:)
  end

  # A namespace for projects: the fields of a manifest of kind Group.
  Group = Data.define(:name, :labels, :created_at, :description) do
    def initialize(name:, labels: {}, created_at: nil, description: nil)
      super
    end

    def kind = 'Group'

    # The manifest Hash with string keys, in the order it is written to disk.
    def to_manifest
      metadata = { 'name' => name, 'labels' => labels.sort.to_h,
                   'creationTimestamp' => Resources.timestamp(created_at) }.compact
      { 'kind' => kind, 'metadata' => metadata, 'spec' => { 'description' => description }.compact }
    end

    def with_labels(labels) = with(labels:)
  end

  # The resource kinds Slipway stores and the words that name them on the command line.
  module Resources
    # One kind: its plural and singular names, extra aliases and the Data class behind it.
    Kind = Data.define(:plural, :singular, :aliases, :klass) do
      # Every word accepted for this kind, matched case-insensitively like kubectl.
      def names = [plural, singular, *aliases]

      def match?(word) = names.include?(word.downcase)

      # Projects live inside a group the way pods live inside a namespace.
      def namespaced? = klass == Project

      # The Kind word of the manifest: Project or Group.
      def title = singular.capitalize
    end

    KINDS = [
      Kind.new(plural: 'projects', singular: 'project', aliases: %w[proj], klass: Project),
      Kind.new(plural: 'groups', singular: 'group', aliases: [], klass: Group)
    ].freeze

    # The Kind named by a command-line word, or Slipway::Error when no kind answers to it.
    def self.resolve(word)
      KINDS.find { it.match?(word) } || raise(Error, "unknown resource type #{word.inspect}")
    end

    # The Kind of a Project or Group value.
    def self.of(resource)
      KINDS.find { resource.is_a?(it.klass) } || raise(ArgumentError, "not a resource: #{resource.inspect}")
    end

    def self.plurals = KINDS.map(&:plural)

    # RFC 3339 in UTC with second precision, or nil; the form creationTimestamp takes on disk.
    def self.timestamp(time) = time&.getutc&.iso8601
  end
end
