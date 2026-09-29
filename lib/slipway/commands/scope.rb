# frozen_string_literal: true

require_relative '../cli/errors'
require_relative '../resources'
require_relative '../selector'

module Slipway
  module Commands
    # Which resources a read verb addresses: the type word, the group in effect, the -A flag
    # and the label selector, resolved from the runtime and the parsed options.
    class Scope
      NONE = 'No resources found.'
      NAMES_WITH_SELECTOR = 'name cannot be provided when a selector is specified'
      NAMES_WITH_ALL_GROUPS = 'a resource cannot be retrieved by name across all groups'

      def initialize(runtime, opts)
        @runtime = runtime
        @opts = opts
      end

      def kind(word) = Resources.resolve(word)

      # The -n flag, else the configured group.
      def group = @runtime.group_for(@opts)

      def all_groups? = @opts[:all_groups] == true

      def selector = Selector.parse(@opts[:selector])

      # The resources named, or every resource of +kind+ in scope that the selector matches.
      # A missing name raises Store::NotFound.
      def select(kind, names)
        return listed(kind) if names.empty?

        check_names(kind)
        names.map { @runtime.store.find(kind, it, group:) }
      end

      # What `get` and `describe` say on stderr when nothing is selected.
      def none_message(kind)
        return NONE if all_groups? || !kind.namespaced?

        "No resources found in #{group} group."
      end

      private

      def listed(kind)
        matcher = selector
        scope_group = kind.namespaced? && !all_groups? ? group : nil
        @runtime.store.list(kind, group: scope_group).select { matcher.match?(it.labels) }
      end

      # kubectl refuses a selector or --all-namespaces next to explicit names.
      def check_names(kind)
        raise CLI::UsageError, NAMES_WITH_SELECTOR unless @opts[:selector].to_s.strip.empty?
        raise CLI::UsageError, NAMES_WITH_ALL_GROUPS if kind.namespaced? && all_groups?
      end
    end
  end
end
