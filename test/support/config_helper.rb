# frozen_string_literal: true

require 'fileutils'
require_relative 'sandbox'

module ConfigHelper
  include Sandbox

  private

  def load(env, config: nil, flags: {})
    Slipway::Config.load(Slipway::Paths.new(env, config:), env:, flags:)
  end

  def config_path(env) = File.join(env['XDG_CONFIG_HOME'], 'slipway', 'config.yaml')

  def write(env, text)
    path = config_path(env)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, text)
  end

  def error_for(env, text)
    write(env, text)
    assert_raises(Slipway::Config::Error) { load(env) }
  end

  def assert_file_error(problem, env, text)
    assert_equal "#{config_path(env)}: #{problem}", error_for(env, text).message
  end

  def assert_config_error(message, env, config: nil)
    error = assert_raises(Slipway::Config::Error) { load(env, config:) }

    assert_equal message, error.message
  end
end
