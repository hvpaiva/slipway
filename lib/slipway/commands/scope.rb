# frozen_string_literal: true

require_relative '../cli/errors'
require_relative '../names'
require_relative '../output'
require_relative '../resources'
require_relative '../selector'
require_relative '../store'

module Slipway
  module Commands
    # Names typed on the command line are checked here, so a bad one is a usage error rather
    # than a failure deep in the store.
    class Scope
      NONE = 'No resources found.'
      NONE_IN = 'No resources found in '
      GROUP_SUFFIX = ' group.'
      NAMES_WITH_SELECTOR = 'name cannot be provided when a selector is specified'
      NAMES_WITH_ALL_GROUPS = 'a resource cannot be retrieved by name across all groups'
      MIXED_TYPES = 'all resources must share one type'
      MIXED_FORMS = 'a name in TYPE/NAME form cannot be combined with a bare name'
      NAME_MISSING = 'missing required argument "NAME"'

      def initialize(runtime, context, opts)
        @runtime = runtime
        @context = context
        @opts = opts
      end

      def kind(word) = Resources.resolve(word)

      # `TYPE/NAME...` is the form `get -o name` prints.
      def targets(words)
        type, *names = words
        kind, names = type.include?('/') ? slashed(words) : [kind(type), names]
        names.each { check_name(kind, it) }
        [kind, names]
      end

      # A verb that acts on repositories names projects alone, bare or in the TYPE/NAME form
      # `get projects -o name` prints, since a group holds no repository of its own.
      def project_targets(words, verb:)
        kind, names = words.any? { it.include?('/') } ? slashed(words) : [Resources::PROJECTS, words]
        raise CLI::UsageError, "cannot #{verb} a group" unless kind == Resources::PROJECTS

        names.each { check_name(kind, it) }
        names
      end

      def target(words)
        kind, names = targets(words)
        raise CLI::UsageError, NAME_MISSING if names.empty?
        raise CLI::UsageError, "unexpected argument #{names[1].inspect}" if names.size > 1

        [kind, names.first]
      end

      def group
        flag = @opts[:group]
        as_usage_error { Names.validate!(flag, what: 'group name') } unless flag.nil?
        @runtime.group_for(@opts)
      end

      def all_groups? = @opts[:all_groups] == true

      def selector = Selector.parse(@opts[:selector])

      # As in kubectl, the resources that exist are shown before the names that do not are
      # reported, one `error:` line each.
      def select(kind, names)
        return yield(listed(kind)) if names.empty?

        check_names(kind)
        found, missing = resolve(kind, names)
        yield found unless found.empty?
        raise Error.new(problems: missing) unless missing.empty?
      end

      def report_none(kind)
        return @context.warn(@context.paint_err(:muted, NONE)) if all_groups? || !kind.namespaced?

        @context.warn(@context.paint_err(:muted, NONE_IN) + @context.paint_err(:string, group) +
                      @context.paint_err(:muted, GROUP_SUFFIX))
      end

      private

      def slashed(words)
        pairs = words.map do |word|
          type, name = word.split('/', 2)
          raise CLI::UsageError, MIXED_FORMS if name.nil?

          [kind(type), name]
        end
        kinds = pairs.map(&:first).uniq
        raise CLI::UsageError, MIXED_TYPES if kinds.size > 1

        [kinds.first, pairs.map(&:last)]
      end

      def check_name(kind, name)
        as_usage_error { Names.validate!(name, what: "#{kind.singular} name") }
      end

      def as_usage_error
        yield
      rescue Names::Invalid => e
        raise CLI::UsageError, e.message
      end

      # A manifest that cannot be read is reported and skipped, so one bad file does not
      # hide the rest of the registry.
      def listed(kind)
        matcher = selector
        scope_group = kind.namespaced? && !all_groups? ? group : nil
        resources = @runtime.store.list(kind, group: scope_group) { Output.warning(@context, it.message) }
        resources.select { matcher.match?(it.labels) }
      end

      def resolve(kind, names)
        found = []
        missing = []
        names.each do |name|
          found << @runtime.store.find(kind, name, group:)
        rescue Store::NotFound => e
          missing << e.message
        end
        [found, missing]
      end

      # kubectl refuses a selector or --all-namespaces next to explicit names.
      def check_names(kind)
        raise CLI::UsageError, NAMES_WITH_SELECTOR unless @opts[:selector].to_s.strip.empty?
        raise CLI::UsageError, NAMES_WITH_ALL_GROUPS if kind.namespaced? && all_groups?
      end
    end
  end
end
