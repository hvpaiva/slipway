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

# A kubectl-style registry for the git repositories on your machine.
module Slipway
  # Entry point shared by exe/slipway and the tests. Returns the process exit status.
  # +runtime_factory+ is called with the context and the parsed options once a verb runs.
  def self.run(argv, context: CLI::Context.system, runtime_factory: Runtime.method(:build))
    registry = Commands.registry(runtime_factory)
    color, theme = Runtime.color_defaults(context, argv)
    CLI::Runner.new(registry, context, color:, theme:).run(argv)
  end
end
