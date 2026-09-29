# frozen_string_literal: true

require 'stringio'
require 'slipway/output'

# Builds contexts whose stdout color is decided up front, so renderer tests can assert exact bytes.
module OutputHelper
  def plain_context
    Slipway::CLI::Context.new(out: StringIO.new, err: StringIO.new)
  end

  def colored_context(theme: 'dark')
    style = Slipway::CLI::Style.for('always', tty: false, env: {}, theme: Slipway::CLI::Theme.fetch(theme))
    Slipway::CLI::Context.new(out: StringIO.new, err: StringIO.new, style:, err_style: style)
  end
end
