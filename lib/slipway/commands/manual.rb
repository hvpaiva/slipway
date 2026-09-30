# frozen_string_literal: true

require_relative '../config'

module Slipway
  module Commands
    # The parts of slipway(1) that belong to no single verb. CLI::Manpage renders them, and
    # bin/generate-man hands them over, because the files and variables they name are slipway's.
    module Manual
      EXIT_STATUSES = {
        '0' => 'Success.',
        '1' => 'Runtime error, such as a missing resource or an unreadable manifest.',
        '2' => 'Usage error: unknown command, unknown flag or invalid argument.',
        '130' => 'Interrupted by SIGINT.'
      }.freeze
      # Every variable the code reads but HOME and PATH, which test/unit/seams_test.rb checks.
      ENVIRONMENT = {
        'SLIPWAY_CONFIG' => 'Path of the configuration file; overridden by --config.',
        'SLIPWAY_DATA_HOME' => 'Directory holding the registry: group and project manifests.',
        'SLIPWAY_COLOR' => 'When to use color (auto, always or never); overridden by --color.',
        'SLIPWAY_THEME' => 'Color theme (dark or light).',
        'SLIPWAY_EDITOR' => 'Editor used by edit; takes precedence over VISUAL and EDITOR.',
        'SLIPWAY_GROUP' => 'Default group scope; overridden by --group.',
        'SLIPWAY_NETWORK_TIMEOUT' => 'Seconds a git network command may run before it is killed.',
        'SLIPWAY_PARALLEL' => 'How many git network commands run at once, from 1 to 16.',
        'SLIPWAY_PROTOCOLS' => 'Transports git may use in network commands, separated by colons (ssh:https).',
        'SLIPWAY_DEBUG' => 'When non-empty, unexpected errors also print their class and backtrace.',
        'NO_COLOR' => 'When non-empty, disables color in auto mode.',
        'FORCE_COLOR' => 'When non-empty, enables color in auto mode even without a terminal.',
        'CLICOLOR_FORCE' => 'Same as FORCE_COLOR.',
        'VISUAL' => 'Editor used by edit when SLIPWAY_EDITOR and the editor configuration key are unset.',
        'EDITOR' => 'Editor used by edit when VISUAL is unset as well.',
        'XDG_CONFIG_HOME' => 'Base of the configuration directory (default ~/.config).',
        'XDG_DATA_HOME' => 'Base of the data directory (default ~/.local/share).',
        'TERM' => 'When dumb, disables color in auto mode.',
        'MANPAGER' => 'When non-empty, slipway man leaves the pager palette alone.',
        'MANROFFOPT' => 'Same as MANPAGER.',
        'LESS_TERMCAP_md' => 'Same as MANPAGER.',
        'GROFF_NO_SGR' => 'Same as MANPAGER.'
      }.freeze
      FILES = {
        '$XDG_CONFIG_HOME/slipway/config.yaml' =>
          'Configuration file; see CONFIGURATION. Also set by --config or SLIPWAY_CONFIG.',
        '$XDG_DATA_HOME/slipway/' =>
          'Registry data: groups/NAME.yaml and projects/GROUP/NAME.yaml. Also set by SLIPWAY_DATA_HOME.'
      }.freeze

      # The keyword arguments CLI::Manpage takes for slipway's own sections.
      def self.sections
        { environment: ENVIRONMENT, files: FILES, configuration: Config::DOCUMENTATION, exit_statuses: EXIT_STATUSES }
      end
    end
  end
end
