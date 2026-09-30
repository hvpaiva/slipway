# frozen_string_literal: true

require_relative 'slipway/version'
require_relative 'slipway/cli'
require_relative 'slipway/paths'
require_relative 'slipway/config'
require_relative 'slipway/editor'
require_relative 'slipway/names'
require_relative 'slipway/labels'
require_relative 'slipway/selector'
require_relative 'slipway/resources'
require_relative 'slipway/manifest'
require_relative 'slipway/store'
require_relative 'slipway/git'
require_relative 'slipway/state'
require_relative 'slipway/output'
require_relative 'slipway/runtime'
require_relative 'slipway/inspector'
require_relative 'slipway/views'
require_relative 'slipway/commands'

# A kubectl-style registry of the git repositories on your machine.
module Slipway
  # Shared by exe/slipway and the tests, so it returns the exit status instead of exiting.
  # +runtime_factory+ is called only once a verb runs, with the context and the parsed options.
  def self.run(argv, context: CLI::Context.system, runtime_factory: Runtime.method(:build))
    registry = Commands.registry(runtime_factory)
    color, theme = Runtime.color_defaults(context, argv)
    CLI::Runner.new(registry, context, color:, theme:).run(argv)
  end
end
