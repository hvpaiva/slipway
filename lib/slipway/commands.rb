# frozen_string_literal: true

require_relative 'version'
require_relative 'cli'
require_relative 'settings'
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
require_relative 'commands/explain'
require_relative 'commands/fetch'
require_relative 'commands/diff'
require_relative 'commands/sync'
require_relative 'commands/rollout'
require_relative 'commands/config'
require_relative 'commands/api_resources'

module Slipway
  module Commands
    PROGRAM = 'slipway'
    DESCRIPTION = 'A kubectl-style registry of the git repositories on your machine'
    LONG_DESCRIPTION = "#{DESCRIPTION}.\n\n" \
                       'A project is a registered git repository. Its manifest can declare where the repository ' \
                       "should be: the remote, the branch and a commit to hold it at.\n\n" \
                       'Projects live in groups the way pods live in namespaces. The group is ' \
                       "\"#{Resources::DEFAULT_GROUP}\", or the one SLIPWAY_GROUP or the group key sets, unless -n " \
                       "is given, and -A covers every group.\n\n" \
                       "#{Options::TYPES_SENTENCE}".freeze
    # Help lists the verbs in this order within their sections.
    VERBS = [Get, Describe, Create, Apply, Delete, Edit, Label, Explain, Fetch, Diff, Sync, Rollout, Config,
             APIResources].freeze

    def self.registry(factory)
      CLI::Registry.new(program: PROGRAM, version: VERSION, description: DESCRIPTION,
                        long_description: LONG_DESCRIPTION, glossaries: Manual.help_glossaries,
                        globals: CLI::Globals.all(group_completer: Options.group_completer(factory)),
                        commands: VERBS.map { it.command(factory) },
                        builtins: { paths: Paths.method(:new) })
    end
  end
end
