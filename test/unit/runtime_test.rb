# frozen_string_literal: true

require 'test_helper'

class RuntimeTest < Minitest::Test
  include Sandbox

  def test_build_assembles_production_collaborators_from_the_context
    with_sandbox do |env|
      runtime = Slipway::Runtime.build(context(env), opts)

      assert_instance_of Slipway::Git::Repository, runtime.git
      assert_instance_of Slipway::Inspector, runtime.inspector
      assert_equal File.join(env['XDG_DATA_HOME'], 'slipway'), runtime.store.root
      assert_equal File.join(env['XDG_CONFIG_HOME'], 'slipway', 'config.yaml'), runtime.paths.config_file
      assert_same env, runtime.env
      assert_predicate runtime.clock.call, :utc?
    end
  end

  def test_build_applies_the_flag_over_the_environment_for_group_and_color
    with_sandbox do |env|
      file = write_config(env, "group: filed\ncolor: never\ntheme: light\n")
      env = env.merge('SLIPWAY_GROUP' => 'envied', 'SLIPWAY_COLOR' => 'always')

      runtime = Slipway::Runtime.build(context(env), opts(config: file, group: 'flagged'))

      assert_equal %w[flagged always light], [runtime.config.group, runtime.config.color, runtime.config.theme]
    end
  end

  def test_build_applies_the_environment_over_the_file
    with_sandbox do |env|
      file = File.join(env['HOME'], 'other.yaml')
      File.write(file, "group: filed\n")
      varied = env.merge('SLIPWAY_GROUP' => 'envied')

      assert_equal 'envied', Slipway::Runtime.build(context(varied), opts(config: file)).config.group
      assert_equal 'filed', Slipway::Runtime.build(context(env), opts(config: file)).config.group
    end
  end

  def test_build_applies_the_file_over_the_defaults
    with_sandbox do |env|
      file = File.join(env['HOME'], 'other.yaml')
      File.write(file, "group: filed\ncolor: never\n")
      filed = Slipway::Runtime.build(context(env), opts(config: file)).config
      defaults = Slipway::Runtime.build(context(env), opts).config

      assert_equal %w[filed never dark], [filed.group, filed.color, filed.theme]
      assert_equal %w[default auto dark], [defaults.group, defaults.color, defaults.theme]
    end
  end

  def test_build_raises_config_errors_for_the_runner_to_report
    with_sandbox do |env|
      file = write_config(env, "colour: always\n")
      error = assert_raises(Slipway::Config::Error) { Slipway::Runtime.build(context(env), opts(config: file)) }

      assert_equal "#{file}: unknown key \"colour\" (known keys: color, editor, group, networkTimeout, " \
                   'protocols, theme)', error.message
      assert_equal 1, error.exit_status
    end
  end

  def test_group_for_prefers_the_flag_over_the_configured_group
    with_sandbox do |env|
      runtime = Slipway::Runtime.build(context(env.merge('SLIPWAY_GROUP' => 'work')), opts)

      assert_equal 'work', runtime.group_for(opts)
      assert_equal 'play', runtime.group_for(opts(group: 'play'))
    end
  end

  def test_color_defaults_come_from_the_default_config_file
    with_sandbox do |env|
      write_config(env, "color: always\ntheme: light\n")

      assert_equal %w[always light], Slipway::Runtime.color_defaults(context(env), %w[get projects])
      assert_equal %w[auto dark], Slipway::Runtime.color_defaults(context(env.merge('XDG_CONFIG_HOME' => '/nowhere')),
                                                                  %w[get projects])
    end
  end

  def test_color_defaults_prescan_the_config_flag_in_both_spellings
    with_sandbox do |env|
      file = File.join(env['HOME'], 'other.yaml')
      File.write(file, "color: never\n")

      assert_equal %w[never dark], Slipway::Runtime.color_defaults(context(env), ['get', '--config', file])
      assert_equal %w[never dark], Slipway::Runtime.color_defaults(context(env), ['get', "--config=#{file}"])
      assert_equal %w[auto dark], Slipway::Runtime.color_defaults(context(env), ['get', '--', '--config', file])
      assert_equal %w[auto dark], Slipway::Runtime.color_defaults(context(env), %w[get --config])
    end
  end

  def test_color_defaults_are_nil_when_the_config_cannot_be_loaded
    with_sandbox do |env|
      write_config(env, "theme: sepia\n")

      assert_equal [nil, nil], Slipway::Runtime.color_defaults(context(env), [])
      assert_equal [nil, nil], Slipway::Runtime.color_defaults(context(env), ['--config', '/missing.yaml'])
    end
  end

  private

  def context(env) = Slipway::CLI::Context.new(out: StringIO.new, err: StringIO.new, env:)

  def opts(config: nil, group: nil, color: nil) = { config:, group:, color: }.freeze

  def write_config(env, text)
    path = File.join(env['XDG_CONFIG_HOME'], 'slipway', 'config.yaml')
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, text)
    path
  end
end
