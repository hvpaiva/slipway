# frozen_string_literal: true

require_relative 'version'
require_relative 'cli'
require_relative 'config'
require_relative 'paths'
require_relative 'commands/manual'
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
require_relative 'commands/fetch'
require_relative 'commands/diff'
require_relative 'commands/sync'
require_relative 'commands/rollout'
require_relative 'commands/config'

module Slipway
  module Commands
    PROGRAM = 'slipway'
    DESCRIPTION = 'A kubectl-style registry of the git repositories on your machine'
    # The space after each newline indents the paragraphs, as kubectl's root help does.
    LONG_DESCRIPTION = "#{DESCRIPTION}.\n\n " \
                       "A project is a registered git repository. get and describe show where each one\n " \
                       "stands, and fetch fetches them all without prompting. Its manifest can also\n " \
                       "declare where the repository should be: the remote, the branch and a commit to\n " \
                       "hold it at. diff shows where a repository differs from that, sync fast-forwards\n " \
                       "the branches that can move without losing work, and rollout undo takes such a\n " \
                       "move back.\n\n " \
                       "Projects live in groups the way pods live in namespaces. The group is\n " \
                       "\"#{Resources::DEFAULT_GROUP}\", or the one SLIPWAY_GROUP or the group key sets, unless -n\n " \
                       "is given, and -A covers every group.\n\n " \
                       "#{Options::TYPES_SENTENCE}".freeze
    # Help lists the verbs in this order within their sections.
    VERBS = [Get, Describe, Create, Apply, Delete, Edit, Label, Fetch, Diff, SyncCommand, RolloutCommand,
             ConfigCommand].freeze

    def self.registry(factory)
      CLI::Registry.new(program: PROGRAM, version: VERSION, description: DESCRIPTION,
                        long_description: LONG_DESCRIPTION,
                        globals: CLI::Globals.all(group_completer: Options.group_completer(factory)),
                        commands: VERBS.map { it.command(factory) },
                        builtins: { paths: Paths.method(:new) })
    end
  end
end
