# frozen_string_literal: true

require_relative '../cli/errors'
require_relative '../names'
require_relative '../resources'
require_relative '../selector'
require_relative '../store'

module Slipway
  module Commands
    # Which resources a verb addresses: the type and names typed as `TYPE NAME...` or
    # `TYPE/NAME...`, the group in effect, the -A flag and the label selector, resolved from
    # the runtime and the parsed options. Names typed on the command line are checked here,
    # so a bad one is a usage error rather than a failure deep in the store.
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

      # The Kind named by +word+, or Slipway::Error listing the kinds that exist.
      def kind(word) = Resources.resolve(word)

      # The [kind, names] the positional +words+ address: `TYPE NAME...`, or `TYPE/NAME...`
      # as `get -o name` prints it. Every name is validated.
      def targets(words)
        type, *names = words
        kind, names = type.include?('/') ? slashed(words) : [kind(type), names]
        names.each { check_name(kind, it) }
        [kind, names]
      end

      # The [kind, name] of a verb that takes exactly one resource.
      def target(words)
        kind, names = targets(words)
        raise CLI::UsageError, NAME_MISSING if names.empty?
        raise CLI::UsageError, "unexpected argument #{names[1].inspect}" if names.size > 1

        [kind, names.first]
      end

      # The -n flag, else the configured group; a flag value that is not a name is a usage error.
      def group
        flag = @opts[:group]
        as_usage_error { Names.validate!(flag, what: 'group name') } unless flag.nil?
        @runtime.group_for(@opts)
      end

      # True when -A asks for every group.
      def all_groups? = @opts[:all_groups] == true

      # The label selector of -l, which selects everything when the flag is absent.
      def selector = Selector.parse(@opts[:selector])

      # Yields the resources +names+ address, or every resource of +kind+ in scope that the
      # selector matches when no name was given. As in kubectl, the resources that exist are
      # shown before the names that do not are reported, one `error:` line each.
      def select(kind, names)
        return yield(listed(kind)) if names.empty?

        check_names(kind)
        found, missing = resolve(kind, names)
        yield found unless found.empty?
        raise Error.new(problems: missing) unless missing.empty?
      end

      # Prints kubectl's notice for an empty selection on stderr, muted, with the group name
      # in the string role.
      def report_none(kind)
        return @context.warn(@context.paint_err(:muted, NONE)) if all_groups? || !kind.namespaced?

        @context.warn(@context.paint_err(:muted, NONE_IN) + @context.paint_err(:string, group) +
                      @context.paint_err(:muted, GROUP_SUFFIX))
      end

      private

      # `TYPE/NAME` words: one kind for all of them, every word in that form.
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
        resources = @runtime.store.list(kind, group: scope_group) do |problem|
          @context.warn("#{@context.paint_err(:warning, 'warning:')} #{problem.message}")
        end
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
