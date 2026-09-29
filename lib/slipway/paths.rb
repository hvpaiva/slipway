# frozen_string_literal: true

module Slipway
  # Where Slipway reads and writes files, following the XDG Base Directory Specification.
  # Reads only the environment Hash it is given, so tests never touch ENV.
  class Paths
    CONFIG_VARIABLE = 'SLIPWAY_CONFIG'
    DATA_HOME_VARIABLE = 'SLIPWAY_DATA_HOME'
    HOME_VARIABLE = 'HOME'
    XDG_CONFIG_HOME = 'XDG_CONFIG_HOME'
    XDG_DATA_HOME = 'XDG_DATA_HOME'
    APP = 'slipway'
    CONFIG_FILE = 'config.yaml'
    MAN_SECTION = File.join('man', 'man1').freeze

    # Defaults relative to HOME, applied when the XDG variable is unset, empty or relative.
    XDG_DEFAULTS = {
      XDG_CONFIG_HOME => '.config',
      XDG_DATA_HOME => File.join('.local', 'share')
    }.freeze

    # +config+ is the value of the --config flag, which outranks every variable.
    def initialize(env, config: nil)
      @env = env
      @config_flag = present(config)
    end

    def home = present(@env[HOME_VARIABLE]) || Dir.home

    # --config, then SLIPWAY_CONFIG, then $XDG_CONFIG_HOME/slipway/config.yaml.
    def config_file
      @config_flag || expand(present(@env[CONFIG_VARIABLE])) || File.join(xdg(XDG_CONFIG_HOME), APP, CONFIG_FILE)
    end

    # True when the user named the file; a missing explicit file is an error, a missing default is not.
    def config_explicit? = !(@config_flag || present(@env[CONFIG_VARIABLE])).nil?

    # SLIPWAY_DATA_HOME, then $XDG_DATA_HOME/slipway; the root of the manifest store.
    def data_home = expand(present(@env[DATA_HOME_VARIABLE])) || File.join(xdg(XDG_DATA_HOME), APP)

    # Where `slipway man --install` copies the pages: $XDG_DATA_HOME/man/man1.
    def man_install_dir = File.join(xdg(XDG_DATA_HOME), MAN_SECTION)

    private

    # The specification says an unset or empty variable takes its default and a relative
    # path is invalid and ignored.
    def xdg(name)
      value = present(@env[name])
      return value if value && File.absolute_path?(value)

      File.join(home, XDG_DEFAULTS.fetch(name))
    end

    def present(value)
      value unless value.nil? || value.empty?
    end

    # A leading ~ refers to the HOME the environment names, not the one Ruby started with.
    def expand(value)
      return value if value.nil?
      return home if value == '~'
      return File.join(home, value.delete_prefix('~/')) if value.start_with?('~/')

      value
    end
  end
end
