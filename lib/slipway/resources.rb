# frozen_string_literal: true

require_relative 'error'

module Slipway
  # The values of spec.syncPolicy, capitalized as Kubernetes enums are (imagePullPolicy: IfNotPresent).
  module SyncPolicy
    FAST_FORWARD = 'FastForward'
    FETCH_ONLY = 'FetchOnly'
    ALL = [FAST_FORWARD, FETCH_ONLY].freeze
  end

  # A registered git repository.
  Project = Data.define(:name, :group, :labels, :created_at, :path, :description, :remote, :branch, :revision,
                        :sync_policy, :paused) do
    def initialize(name:, path:, group: 'default', labels: {}, created_at: nil, description: nil, remote: nil,
                   branch: nil, revision: nil, sync_policy: SyncPolicy::FAST_FORWARD, paused: false)
      super
    end

    def kind = 'Project'

    # Key order here is the order written to disk.
    def to_manifest
      metadata = { 'name' => name, 'group' => group, 'labels' => labels.sort.to_h,
                   'creationTimestamp' => Resources.timestamp(created_at) }.compact
      { 'kind' => kind, 'metadata' => metadata, 'spec' => spec }
    end

    def with_labels(labels) = with(labels:)

    private

    # A field at its default is left out, so a manifest written before the field existed is
    # written back byte for byte and apply reads it as unchanged.
    def spec
      { 'path' => path, 'description' => description, 'remote' => remote, 'branch' => branch,
        'revision' => revision, 'syncPolicy' => (sync_policy unless sync_policy == SyncPolicy::FAST_FORWARD),
        'paused' => (true if paused) }.compact
    end
  end

  Group = Data.define(:name, :labels, :created_at, :description) do
    def initialize(name:, labels: {}, created_at: nil, description: nil)
      super
    end

    def kind = 'Group'

    # Key order here is the order written to disk.
    def to_manifest
      metadata = { 'name' => name, 'labels' => labels.sort.to_h,
                   'creationTimestamp' => Resources.timestamp(created_at) }.compact
      { 'kind' => kind, 'metadata' => metadata, 'spec' => { 'description' => description }.compact }
    end

    def with_labels(labels) = with(labels:)
  end

  module Resources
    Kind = Data.define(:plural, :singular, :aliases, :klass) do
      def names = [plural, singular, *aliases]

      # Case-insensitive, like kubectl.
      def match?(word) = names.include?(word.downcase)

      # Projects live inside a group the way pods live inside a namespace.
      def namespaced? = klass == Project

      def title = singular.capitalize
    end

    PROJECTS = Kind.new(plural: 'projects', singular: 'project', aliases: %w[proj], klass: Project)
    GROUPS = Kind.new(plural: 'groups', singular: 'group', aliases: [], klass: Group)
    KINDS = [PROJECTS, GROUPS].freeze
    # Created on first use.
    DEFAULT_GROUP = 'default'

    def self.resolve(word)
      KINDS.find { it.match?(word) } ||
        raise(Error, "unknown resource type #{word.inspect} (known types: #{KINDS.map(&:plural).join(', ')})")
    end

    def self.of(resource)
      KINDS.find { resource.is_a?(it.klass) } || raise(ArgumentError, "not a resource: #{resource.inspect}")
    end

    # RFC 3339 in UTC with second precision, the form creationTimestamp takes on disk.
    def self.timestamp(time) = time&.getutc&.iso8601
  end
end
