# frozen_string_literal: true

require_relative 'slipway/version'
require_relative 'slipway/cli'
require_relative 'slipway/names'
require_relative 'slipway/labels'
require_relative 'slipway/selector'
require_relative 'slipway/resources'
require_relative 'slipway/manifest'
require_relative 'slipway/store'

# A kubectl-style registry for the git repositories on your machine.
module Slipway
  # Entry point shared by exe/slipway and the tests. Returns the process exit status.
  def self.run(argv, context: CLI::Context.system, runtime_factory: Runtime.method(:build))
    registry = Commands.registry(runtime_factory)
    CLI::Runner.new(registry, context).run(argv)
  end
end
