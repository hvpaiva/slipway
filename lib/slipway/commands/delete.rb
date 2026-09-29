# frozen_string_literal: true

require_relative 'base'
require_relative '../store'

module Slipway
  module Commands
    # `slipway delete TYPE NAME...`: removes resources by name, resolving every name first.
    class Delete < Base
      DESCRIPTION = "Delete resources by type and name.\n\n" \
                    'Every name is resolved before anything is deleted, so a name that does not exist leaves ' \
                    'the others untouched unless --ignore-not-found is set. Deleting a group also deletes the ' \
                    "registrations of its projects; the default group cannot be deleted.\n\n" \
                    "Deleting a project removes its registration only. The repository on disk is not touched.\n\n" \
                    "#{Options::TYPES_SENTENCE}".freeze
      USAGE = '(TYPE NAME... | TYPE/NAME...)'
      NO_NAMES = 'resource(s) were provided, but no name was specified'

      IGNORE_NOT_FOUND = CLI::Option.new(long: 'ignore-not-found',
                                         description: 'Treat "resource not found" as a successful delete.')

      # The registry entry for `delete`: names completed from the store, --dry-run and --ignore-not-found.
      def self.command(factory)
        CLI::Command.new(
          name: 'delete', summary: 'Delete resources by type and name', section: 'Basic Commands',
          description: DESCRIPTION, examples:, usage: USAGE,
          positionals: [Options::TYPE, Options.name_positional(factory, variadic: true, required: false)],
          options: [Options::DRY_RUN, IGNORE_NOT_FOUND],
          handler: new(factory)
        )
      end

      def self.examples
        [
          CLI::Example.new(comment: 'Delete a project from the current group', command: 'delete project hldr'),
          CLI::Example.new(comment: 'Delete two projects from the work group',
                           command: 'delete projects api web -n work'),
          CLI::Example.new(comment: 'Delete a group and the registrations of its projects',
                           command: 'delete group work'),
          CLI::Example.new(comment: 'Delete a project if it exists, quietly otherwise',
                           command: 'delete project hldr --ignore-not-found')
        ]
      end
      private_class_method :examples

      # Resolves every name, then deletes them in order and prints one line each.
      def run(runtime, context, args, opts)
        scope = scope(runtime, context, opts)
        kind, names = scope.targets(args)
        raise CLI::UsageError, NO_NAMES if names.empty?

        group = kind.namespaced? ? scope.group : nil
        dry_run = opts[:dry_run] == 'client'
        resolve(runtime.store, kind, names.uniq, group, ignore: opts[:ignore_not_found] == true).each do |resource|
          runtime.store.delete(kind, resource.name, group:) unless dry_run
          context.puts(line(context, kind, resource, dry_run:))
        end
      end

      private

      # Every named resource, in order, or the first failure before anything is removed.
      def resolve(store, kind, names, group, ignore:)
        names.filter_map do |name|
          raise Error, Store::PROTECTED_GROUP if !kind.namespaced? && name == Store::DEFAULT_GROUP

          store.find(kind, name, group:)
        rescue Store::NotFound
          raise unless ignore

          nil
        end
      end

      # kubectl's form: `project "hldr" deleted from work group`, `group "work" deleted`.
      def line(context, kind, resource, dry_run:)
        parts = ["#{kind.singular} #{resource.name.inspect}", context.paint(:delete_deleted, 'deleted')]
        parts << "from #{resource.group} group" if kind.namespaced?
        parts << context.paint(:dry_run, '(dry run)') if dry_run
        parts.join(' ')
      end
    end
  end
end
