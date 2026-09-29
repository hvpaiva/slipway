# frozen_string_literal: true

module Slipway
  module CLI
    # The options every command accepts. The Runner reads help, version and color from the
    # parsed values by these keys, so a registry passes ALL as its globals.
    module Globals
      COLOR = Option.new(long: 'color', argument: 'WHEN', optional: true, implicit: 'always', default: 'auto',
                         enum: Style::MODES, description: 'When to use color in the output.')
      GROUP = Option.new(long: 'group', short: 'n', argument: 'NAME', description: 'The group scope for this request.')
      CONFIG = Option.new(long: 'config', argument: 'PATH', description: 'Path to the configuration file.')
      HELP = Option.new(long: 'help', short: 'h', description: 'Print help and exit.')
      VERSION = Option.new(long: 'version', short: 'V', description: 'Print the version and exit.')

      ALL = [COLOR, GROUP, CONFIG, HELP, VERSION].freeze
    end
  end
end
