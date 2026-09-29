# frozen_string_literal: true

require_relative 'version'
require_relative 'cli'
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
    # Help lists the verbs in this order within their sections.
    VERBS = [Get, Describe, Create, Apply, Delete, Edit, Label, Config].freeze

    # The complete registry: every verb built with +factory+, plus the builtins.
    def self.registry(factory)
      CLI::Registry.new(program: PROGRAM, version: VERSION, description: DESCRIPTION,
                        globals: CLI::Globals::ALL, commands: VERBS.map { it.command(factory) })
    end
  end
end
