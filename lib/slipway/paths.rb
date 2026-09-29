# frozen_string_literal: true

module Slipway
  # Follows the XDG Base Directory Specification. Reads only the environment Hash it is
  # given, so tests never touch ENV.
  class Paths
    CONFIG_VARIABLE = 'SLIPWAY_CONFIG'
    DATA_HOME_VARIABLE = 'SLIPWAY_DATA_HOME'
    HOME_VARIABLE = 'HOME'
    XDG_CONFIG_HOME = 'XDG_CONFIG_HOME'
    XDG_DATA_HOME = 'XDG_DATA_HOME'
    APP = 'slipway'
    CONFIG_FILE = 'config.yaml'
    MAN_SECTION = File.join('man', 'man1').freeze
    TILDE = %r{\A~(?=/|\z)}

    XDG_DEFAULTS = {
      XDG_CONFIG_HOME => '.config',
      XDG_DATA_HOME => File.join('.local', 'share')
    }.freeze

    # Only a bare `~` or `~/` is expanded; `~user` forms and relative paths stay as written.
    def self.expand(value, home:) = value&.sub(TILDE, home)

    def initialize(env, config: nil)
      @env = env
      @config_flag = present(config)
    end

    def home = present(@env[HOME_VARIABLE]) || Dir.home

    def config_file
      @config_flag || expand(present(@env[CONFIG_VARIABLE])) || File.join(xdg(XDG_CONFIG_HOME), APP, CONFIG_FILE)
    end

    # A missing explicit file is an error, a missing default is not.
    def config_explicit? = !(@config_flag || present(@env[CONFIG_VARIABLE])).nil?

    def data_home = expand(present(@env[DATA_HOME_VARIABLE])) || File.join(xdg(XDG_DATA_HOME), APP)

    def man_install_dir = File.join(xdg(XDG_DATA_HOME), MAN_SECTION)

    # The one user directory man-db searches on its own, when ~/.local/bin is on PATH.
    def man_db_dir = File.join(home, XDG_DEFAULTS.fetch(XDG_DATA_HOME), MAN_SECTION)

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
    def expand(value) = self.class.expand(value, home:)
  end
end
