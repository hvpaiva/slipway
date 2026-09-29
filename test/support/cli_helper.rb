# frozen_string_literal: true

require 'stringio'

# Runs the command line in-process with StringIO streams and a Hash environment.
module CliHelper
  # Returns [status, stdout, stderr]. A +registry+ runs through the Runner alone; otherwise
  # the whole program runs through Slipway.run, with +runtime+ replacing the production one.
  def run_cli(*argv, env: {}, tty: false, err_tty: tty, registry: nil, runtime: nil)
    out = StringIO.new
    err = StringIO.new
    context = Slipway::CLI::Context.new(out:, err:, env:, tty:, err_tty:)
    status = run_program(argv, context, registry, runtime)
    [status, out.string, err.string]
  end

  private

  def run_program(argv, context, registry, runtime)
    return Slipway::CLI::Runner.new(registry, context).run(argv) if registry
    return Slipway.run(argv, context:) unless runtime

    Slipway.run(argv, context:, runtime_factory: ->(_context, _opts) { runtime })
  end
end
