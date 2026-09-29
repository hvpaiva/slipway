# frozen_string_literal: true

require_relative 'registry'
require_relative 'style'

module Slipway
  module CLI
    # The options every command accepts. The Runner reads help, version and color from the
    # parsed values by these keys, so a registry passes ALL as its globals.
    module Globals
      # No default: a nil value tells a handler the flag was not typed, so SLIPWAY_COLOR and the
      # config file can still decide. The Runner falls back to auto on its own.
      COLOR = Option.new(long: 'color', argument: 'WHEN', optional: true, implicit: 'always', enum: Style::MODES,
                         description: 'When to use color in the output; a bare --color means always.')
      GROUP = Option.new(long: 'group', short: 'n', argument: 'NAME', description: 'The group scope for this request.')
      CONFIG = Option.new(long: 'config', argument: 'PATH', description: 'Path to the configuration file.')
      HELP = Option.new(long: 'help', short: 'h', description: 'Print help and exit.')
      VERSION = Option.new(long: 'version', short: 'V', description: 'Print the version and exit.')

      ALL = [COLOR, GROUP, CONFIG, HELP, VERSION].freeze

      # ALL with -n completing group names through +group_completer+, a proc that receives
      # the words typed so far and returns the candidates.
      def self.all(group_completer:)
        ALL.map { it.equal?(GROUP) ? it.with(completer: group_completer) : it }.freeze
      end
    end
  end
end
