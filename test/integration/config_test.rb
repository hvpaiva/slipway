# frozen_string_literal: true

require 'test_helper'

class ConfigIntegrationTest < Minitest::Test
  include IntegrationHelper

  def test_view_shows_the_defaults_and_says_the_file_is_missing
    with_home do |env|
      status, out, err = slipway('config', 'view', env:)

      assert_equal [0, ''], [status, err]
      assert_equal "# #{config_file(env)} (not found)\ncolor: auto\neditor:\ngroup: default\ntheme: dark\n", out
      assert_equal [0, "#{config_file(env)}\n", ''], slipway('config', 'path', env:)
    end
  end

  def test_view_reads_the_file_and_flags_outrank_it
    with_home do |env|
      path = write_config(env, "color: always\ntheme: light\ngroup: work\neditor: nano\n")

      assert_equal "\e[90;3m# #{path}\e[0m\ncolor: always\neditor: nano\ngroup: work\ntheme: light\n",
                   slipway!('config', 'view', env:)
      assert_equal "# #{path}\ncolor: never\neditor: nano\ngroup: home\ntheme: light\n",
                   slipway!('config', 'view', '--color=never', '-n', 'home', env:)
    end
  end

  def test_variables_outrank_the_file
    with_home do |env|
      path = write_config(env, "color: always\ntheme: light\n")
      env = env.merge('SLIPWAY_COLOR' => 'never', 'SLIPWAY_THEME' => 'dark', 'SLIPWAY_GROUP' => 'work',
                      'SLIPWAY_EDITOR' => 'vim')

      assert_equal "# #{path}\ncolor: never\neditor: vim\ngroup: work\ntheme: dark\n", slipway!('config', 'view', env:)
    end
  end

  # SLIPWAY_COLOR and SLIPWAY_THEME are read by the command layer before the configuration
  # loads, so their errors name the value; SLIPWAY_GROUP is validated with the file's wording.
  def test_an_invalid_variable_is_a_runtime_error
    with_home do |env|
      assert_equal [1, '', "error: SLIPWAY_THEME: must be one of dark, light\n"],
                   slipway('config', 'view', env: env.merge('SLIPWAY_THEME' => 'solarized'))
      assert_equal [1, '', "error: SLIPWAY_COLOR: must be one of auto, always, never\n"],
                   slipway('config', 'view', env: env.merge('SLIPWAY_COLOR' => 'sometimes'))
      assert_equal [1, '', "error: SLIPWAY_GROUP: must be a valid group name: #{Slipway::Names::RULE}\n"],
                   slipway('config', 'view', env: env.merge('SLIPWAY_GROUP' => 'Bad_Group'))
    end
  end

  def test_the_config_flag_and_slipway_config_name_another_file
    with_home do |env|
      other = File.join(env['HOME'], 'work.yaml')
      File.write(other, "group: work\n")

      assert_equal "# #{other}\ncolor: auto\neditor:\ngroup: work\ntheme: dark\n",
                   slipway!('config', 'view', '--config', other, env:)
      assert_equal "#{other}\n", slipway!('config', 'path', "--config=#{other}", env:)
      assert_equal "#{other}\n", slipway!('config', 'path', env: env.merge('SLIPWAY_CONFIG' => other))
      assert_equal "#{other}\n", slipway!('config', 'path', env: env.merge('SLIPWAY_CONFIG' => '~/work.yaml'))
    end
  end

  def test_a_named_file_has_to_exist
    with_home do |env|
      assert_equal [1, '', "error: /nonexistent.yaml: no such file\n"],
                   slipway('config', 'view', '--config', '/nonexistent.yaml', env:)
      assert_equal [1, '', "error: #{env['HOME']}/x.yaml: no such file\n"],
                   slipway('get', 'projects', env: env.merge('SLIPWAY_CONFIG' => "#{env['HOME']}/x.yaml"))
    end
  end

  def test_a_broken_file_fails_every_command_with_its_path
    with_home do |env|
      path = write_config(env, "colour: always\n")
      message = "error: #{path}: unknown key \"colour\" (known keys: color, editor, group, theme)\n"

      assert_equal [1, '', message], slipway('config', 'view', env:)
      assert_equal [1, '', message], slipway('get', 'projects', env:)

      write_config(env, "theme: blue\n")

      assert_equal [1, '', "error: #{path}: \"theme\" must be one of dark, light\n"], slipway('config', 'view', env:)

      write_config(env, "- just\n- a list\n")

      assert_equal [1, '', "error: #{path}: expected a mapping of keys to values\n"], slipway('config', 'path', env:)
    end
  end

  def test_the_group_alone_prints_its_help_and_rejects_unknown_subcommands
    with_home do |env|
      status, out, err = slipway('config', env:)

      assert_equal [0, ''], [status, err]
      assert_equal <<~TEXT, out
        Inspect the configuration that slipway resolved from flags, environment variables and the configuration file.

        Available Commands:
          view            Display the configuration in effect
          path            Display the path of the configuration file

        Usage:
          slipway config COMMAND [flags]

        Use "slipway config <command> --help" for more information about a given command.
        Use "slipway --help" for a list of global options (applies to all commands).
      TEXT
      assert_equal [2, '', "error: unknown command \"bogus\" for \"slipway config\"\n" \
                           "Run 'slipway config --help' for usage.\n"], slipway('config', 'bogus', env:)
    end
  end
end
