# frozen_string_literal: true

require_relative '../settings'
require_relative '../git'

module Slipway
  module Commands
    # The parts of slipway(1) and of the root `--help` that belong to no single verb. CLI::Manpage
    # renders them, and bin/generate-man hands them over, because the files and variables they
    # name are slipway's.
    module Manual
      EXIT_STATUSES = {
        '0' => 'Success.',
        '1' => 'Runtime error, such as a missing resource or an unreadable manifest.',
        '2' => 'Usage error: unknown command, unknown flag or invalid argument.',
        '130' => 'Interrupted by SIGINT.'
      }.freeze
      CONFIG_FILE = '$XDG_CONFIG_HOME/slipway/config.yaml'
      SETTING_VARIABLES = [['color', '; --color outranks both'], ['theme'], ['editor', ', VISUAL and EDITOR'],
                           ['group', '; --group outranks both'], ['networkTimeout'], ['parallel'],
                           ['protocols', '; the names are separated by colons, as in ssh:https']].freeze

      # A setting's variable points at the `section` that describes its value, so the value is
      # described once.
      def self.setting(key, rest, section:)
        variable = Settings::ALL.find { it.key == key }.variable
        [variable, "Outranks the #{key} key (see #{section})#{rest}."]
      end
      private_class_method :setting

      def self.own_variables(section)
        { 'SLIPWAY_CONFIG' => 'Path of the configuration file; overridden by --config.',
          'SLIPWAY_DATA_HOME' => 'Directory holding the registry: group and project manifests.',
          **SETTING_VARIABLES.to_h { |key, rest = ''| setting(key, rest, section:) },
          'SLIPWAY_DEBUG' => 'When non-empty, unexpected errors also print their class and backtrace.' }
      end
      private_class_method :own_variables

      # Every variable the code reads but HOME and PATH, which test/unit/seams_test.rb checks.
      ENVIRONMENT = {
        **own_variables('CONFIGURATION'),
        'NO_COLOR' => 'When non-empty, disables color in auto mode.',
        'FORCE_COLOR' => 'When non-empty, enables color in auto mode even without a terminal.',
        'CLICOLOR_FORCE' => 'Same as FORCE_COLOR.',
        'VISUAL' => 'Editor used by edit when SLIPWAY_EDITOR and the editor configuration key are unset.',
        'EDITOR' => 'Editor used by edit when VISUAL is unset as well.',
        'XDG_CONFIG_HOME' => 'Base of the configuration directory (default ~/.config).',
        'XDG_DATA_HOME' => 'Base of the data directory (default ~/.local/share).',
        'TERM' => 'When dumb, disables color in auto mode.',
        'COLUMNS' => "Width help wraps at in place of the terminal's, at most 100.",
        'MANPAGER' => 'When non-empty, slipway man leaves the pager palette alone.',
        'MANROFFOPT' => 'Same as MANPAGER.',
        'LESS_TERMCAP_md' => 'Same as MANPAGER.',
        'GROFF_NO_SGR' => 'Same as MANPAGER.'
      }.freeze
      # The variables slipway clears for git instead of reading them.
      CLEARED = {
        Git::Runner::ENVIRONMENT.filter_map { |name, value| name if value.nil? && name.start_with?('GIT_') }
                                .join(', ') =>
          'Ignored: every git command slipway runs starts without them, so an inherited value cannot point git at ' \
          'another repository.'
      }.freeze
      FILES = {
        CONFIG_FILE => 'Configuration file; see CONFIGURATION. Also set by --config or SLIPWAY_CONFIG.',
        '$XDG_DATA_HOME/slipway/' =>
          'Registry data: groups/NAME.yaml and projects/GROUP/NAME.yaml. Also set by SLIPWAY_DATA_HOME.'
      }.freeze

      # The keyword arguments CLI::Manpage takes for slipway's own sections.
      def self.sections
        { environment: ENVIRONMENT.merge(CLEARED), files: FILES, configuration: Settings::DOCUMENTATION,
          exit_statuses: EXIT_STATUSES }
      end

      def self.help_glossaries
        [CLI::Glossary.new(title: 'Environment Variables', entries: own_variables('Configuration File'),
                           intro: 'slipway man lists the other variables slipway reads, such as NO_COLOR.'),
         CLI::Glossary.new(title: 'Configuration File', entries: Settings::DOCUMENTATION,
                           intro: "#{CONFIG_FILE}, or the file --config or SLIPWAY_CONFIG names, sets these keys.")]
      end
    end
  end
end
