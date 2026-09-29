# frozen_string_literal: true

require 'did_you_mean'
require_relative 'cli/errors'
require_relative 'cli/theme'
require_relative 'cli/style'
require_relative 'cli/context'
require_relative 'cli/registry'
require_relative 'cli/globals'
require_relative 'cli/parser'
require_relative 'cli/validator'
require_relative 'cli/help_renderer'
require_relative 'cli/completer'
require_relative 'cli/completion_scripts'
require_relative 'cli/builtins'
require_relative 'cli/runner'

module Slipway
  # The command layer: a data-driven registry, an OptionParser-backed front controller,
  # a kubectl-style help renderer and a registry-driven completer.
  module CLI
  end
end
