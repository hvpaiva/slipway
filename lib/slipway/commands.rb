# frozen_string_literal: true

require_relative 'version'
require_relative 'cli'
require_relative 'config'
require_relative 'paths'
require_relative 'commands/options'
require_relative 'commands/base'
require_relative 'commands/scope'
require_relative 'commands/get'
require_relative 'commands/describe'
require_relative 'commands/create'
require_relative 'commands/apply'
require_relative 'commands/delete'
require_relative 'commands/edit'
require_relative 'commands/label'
require_relative 'commands/config'

module Slipway
  # The verbs of the program, one class per file, and the registry that dispatches them.
  module Commands
    PROGRAM = 'slipway'
    DESCRIPTION = 'A kubectl-style registry for the git repositories on your machine'
    # What `slipway --help` and the root man page open with, in kubectl's shape: the one-line
    # summary, then indented paragraphs that name the resources and how they are scoped.
    LONG_DESCRIPTION = "#{DESCRIPTION}.\n\n " \
                       "A project is a registered git repository: its path, an optional description\n " \
                       "and labels. Projects live in groups the way pods live in namespaces; the group\n " \
                       "is \"#{Resources::DEFAULT_GROUP}\" unless -n is given, and -A lists every group.\n\n " \
                       "#{Options::TYPES_SENTENCE}".freeze
    # Help lists the verbs in this order within their sections.
    VERBS = [Get, Describe, Create, Apply, Delete, Edit, Label, ConfigCommand].freeze

    # The complete registry: every verb built with +factory+, the builtins wired to the
    # paths of the data home, and -n completing group names from the store.
    def self.registry(factory)
      CLI::Registry.new(program: PROGRAM, version: VERSION, description: DESCRIPTION,
                        long_description: LONG_DESCRIPTION,
                        globals: CLI::Globals.all(group_completer: Options.group_completer(factory)),
                        commands: VERBS.map { it.command(factory) },
                        builtins: { paths: Paths.method(:new) })
    end
  end
end
