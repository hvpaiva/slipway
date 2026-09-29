# frozen_string_literal: true

require 'stringio'

module CliHelper
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
