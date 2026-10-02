# frozen_string_literal: true

require_relative 'base'
require_relative '../labels'

module Slipway
  module Commands
    class Label < Base
      DESCRIPTION = <<~TEXT.chomp
        Update the labels on a resource.

          *  A label key and value must begin with a letter or number, and may contain letters, numbers, hyphens, dots, and underscores, up to 63 characters each.
          *  Optionally, the key can begin with a DNS subdomain prefix and a single '/', like example.com/my-app.
          *  If --overwrite is true, then existing labels can be overwritten, otherwise attempting to overwrite a label will result in an error.
          *  KEY- removes the label KEY; removing a label that is not set changes nothing. A change that leaves the labels as they were prints not labeled.

        #{Options::TYPES_SENTENCE}
      TEXT
      NO_CHANGES = 'at least one label update is required'
      LABELED = 'labeled'
      UNLABELED = 'unlabeled'
      NOT_LABELED = 'not labeled'

      OVERWRITE = CLI::Option.new(long: 'overwrite', summary: 'Allow labels to be overwritten',
                                  description: 'If true, allow labels to be overwritten, otherwise reject label ' \
                                               'updates that overwrite existing labels.')
      LIST = CLI::Option.new(long: 'list',
                             description: 'If true, display the labels for a given resource instead of writing them.')
      CHANGE = CLI::Positional.new(name: 'KEY=VALUE|KEY-', required: false, variadic: true,
                                   description: 'A label to set, as KEY=VALUE, or to remove, as KEY-.')
      USAGE = "(<TYPE> <NAME> | <TYPE/NAME>) #{CHANGE.usage}".freeze

      Change = Data.define(:sets, :removals) do
        # A malformed, repeated or contradictory word is a usage error.
        def self.parse(words) = new(*Labels.parse_changes(words))

        def empty? = sets.empty? && removals.empty?

        # Refuses a silent overwrite with kubectl's error message.
        def apply(labels, overwrite:)
          sets.each do |key, value|
            next if overwrite || !labels.key?(key) || labels[key] == value

            raise Error, "'#{key}' already has a value (#{labels[key]}), and --overwrite is false"
          end
          labels.merge(sets).except(*removals)
        end

        def outcome(labels)
          return [LABELED, :label_labeled] if sets.any? { |key, value| labels[key] != value }
          return [UNLABELED, :label_unlabeled] if removals.any? { labels.key?(it) }

          [NOT_LABELED, :label_not_labeled]
        end
      end

      def self.command(factory)
        CLI::Command.new(
          name: 'label', summary: 'Update the labels on a resource', section: 'Basic Commands',
          description: DESCRIPTION, examples:, usage: USAGE,
          positionals: [Options::TYPE, Options.name_positional(factory, variadic: false, required: false), CHANGE],
          options: [OVERWRITE, LIST, Options::DRY_RUN],
          handler: new(factory)
        )
      end

      def self.examples
        [
          CLI::Example.new(comment: "Update project 'hldr' with the label 'lang' and the value 'rust'",
                           command: 'label project hldr lang=rust'),
          CLI::Example.new(comment: "Update project 'hldr' with the label 'lang' and the value 'go', overwriting " \
                                    'any existing value', command: 'label project hldr lang=go --overwrite'),
          CLI::Example.new(comment: "Remove the label 'tier' from project 'hldr'", command: 'label project hldr tier-'),
          CLI::Example.new(comment: "List the labels of group 'work'", command: 'label group work --list')
        ]
      end
      private_class_method :examples

      def kinds = Resources::KINDS

      def run(runtime, context, args, opts)
        scope = scope(runtime, context, opts)
        kind, name, words = split(scope, args)
        change = Change.parse(words)
        raise CLI::UsageError, NO_CHANGES if change.empty? && opts[:list] != true

        resource = runtime.store.find(kind, name, group: kind.namespaced? ? scope.group : nil)
        labels = change.apply(resource.labels, overwrite: opts[:overwrite] == true)
        return list(context, labels) if opts[:list] == true

        write(runtime.store, context, kind, resource.with_labels(labels), change.outcome(resource.labels),
              dry_run: opts[:dry_run] == true)
      end

      private

      def split(scope, args)
        type, *rest = args
        return [*scope.target([type]), rest] if type.include?('/')

        [*scope.target([type, *rest.first(1)]), rest.drop(1)]
      end

      def write(store, context, kind, resource, (word, role), dry_run:)
        store.save(resource) unless dry_run || word == NOT_LABELED
        result_line(context, kind, resource.name, word, role, dry_run:)
      end

      # `--list` computes the labels without writing them, as kubectl does.
      def list(context, labels)
        labels.sort.each { |key, value| context.puts("#{key}=#{value}") }
      end
    end
  end
end
