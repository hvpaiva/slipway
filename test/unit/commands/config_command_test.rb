# frozen_string_literal: true

require 'test_helper'

class ConfigCommandTest < Minitest::Test
  include CommandsHelper

  NETWORK = "networkTimeout: 60\nprotocols:\n- ssh\n- https\n"
  DEFAULTS = "color: auto\neditor:\ngroup: default\n#{NETWORK}theme: dark\n".freeze

  def test_view_without_a_file_prints_the_defaults_under_a_not_found_comment
    with_sandbox do |env|
      expected = "# #{default_path(env)} (not found)\n#{DEFAULTS}"

      assert_equal [0, expected, ''], run_config('config', 'view', env:)
    end
  end

  def test_view_prints_the_values_of_the_file
    with_sandbox do |env|
      path = write_config(env, "color: never\ntheme: light\neditor: code --wait\ngroup: work\n")

      assert_equal [0, "# #{path}\ncolor: never\neditor: code --wait\ngroup: work\n#{NETWORK}theme: light\n", ''],
                   run_config('config', 'view', env:)
    end
  end

  def test_view_shows_environment_variables_over_the_file
    with_sandbox do |env|
      path = write_config(env, "color: never\ntheme: light\neditor: nano\ngroup: work\n")
      env = env.merge('SLIPWAY_COLOR' => 'always', 'SLIPWAY_THEME' => 'dark', 'SLIPWAY_EDITOR' => 'vim',
                      'SLIPWAY_GROUP' => 'home')

      status, out, err = run_config('config', 'view', env:)

      assert_equal [0, ''], [status, err]
      assert_equal "color: always\neditor: vim\ngroup: home\n#{NETWORK}theme: dark\n", out.lines[1..].join
      assert_includes out.lines.first, "# #{path}"
    end
  end

  def test_view_shows_flags_over_everything_else
    with_sandbox do |env|
      write_config(env, "color: never\ngroup: work\n")
      env = env.merge('SLIPWAY_GROUP' => 'home')

      _, out, = run_config('config', 'view', '--color=never', '-n', 'lab', env:)

      assert_equal "color: never\neditor:\ngroup: lab\n#{NETWORK}theme: dark\n", out.lines[1..].join
    end
  end

  def test_view_reads_the_file_named_by_config
    with_sandbox do |env|
      other = File.join(env['HOME'], 'other.yaml')
      File.write(other, "theme: light\n")

      assert_equal [0, "# #{other}\ncolor: auto\neditor:\ngroup: default\n#{NETWORK}theme: light\n", ''],
                   run_config('config', 'view', '--config', other, env:)
      assert_equal [0, "#{other}\n", ''], run_config('config', 'path', "--config=#{other}", env:)
    end
  end

  def test_a_missing_explicit_file_is_an_error
    with_sandbox do |env|
      missing = File.join(env['HOME'], 'missing.yaml')

      assert_equal [1, '', "error: #{missing}: no such file\n"], run_config('config', 'view', '--config', missing, env:)
      assert_equal [1, '', "error: #{missing}: no such file\n"],
                   run_config('config', 'path', env: env.merge('SLIPWAY_CONFIG' => missing))
    end
  end

  def test_a_broken_file_is_reported_with_exit_one
    with_sandbox do |env|
      path = write_config(env, "colour: always\n")

      assert_equal [1, '', "error: #{path}: unknown key \"colour\" (known keys: color, editor, group, " \
                           "networkTimeout, protocols, theme)\n"], run_config('config', 'view', env:)
    end
  end

  def test_the_comment_is_painted_muted_and_the_values_are_left_plain
    with_sandbox do |env|
      _, out, = run_config('config', 'view', '--color', env:)

      assert_equal "\e[90;3m# #{default_path(env)} (not found)\e[0m\ncolor: always\neditor:\ngroup: default\n" \
                   "#{NETWORK}theme: dark\n", out
    end
  end

  def test_path_prints_the_default_file_and_says_on_stderr_when_it_is_missing
    with_sandbox do |env|
      note = "The file does not exist; slipway uses its defaults.\n"

      assert_equal [0, "#{default_path(env)}\n", note], run_config('config', 'path', env:)
      assert_equal [0, "#{default_path(env)}\n", note],
                   run_config('config', 'path', env: env.merge('XDG_CONFIG_HOME' => 'rel'))
    end
  end

  def test_path_leaves_stderr_empty_when_the_file_exists
    with_sandbox do |env|
      path = write_config(env, '')

      assert_equal [0, "#{path}\n", ''], run_config('config', 'path', env:)

      named = File.join(env['HOME'], 'named.yaml')
      File.write(named, '')

      assert_equal [0, "#{named}\n", ''], run_config('config', 'path', env: env.merge('SLIPWAY_CONFIG' => named))
    end
  end

  def test_path_paints_the_note_with_the_stderr_style_and_leaves_the_path_plain
    with_sandbox do |env|
      path = "#{default_path(env)}\n"
      note = 'The file does not exist; slipway uses its defaults.'
      terminal = env.except('TERM')

      assert_equal [0, path, "\e[90;3m#{note}\e[0m\n"], run_config('config', 'path', '--color=always', env:)
      assert_equal [0, path, "\e[90;3m#{note}\e[0m\n"],
                   run_config('config', 'path', env: terminal, tty: false, err_tty: true)
      assert_equal [0, path, "#{note}\n"], run_config('config', 'path', env: terminal, tty: true, err_tty: false)
    end
  end

  def test_the_group_alone_prints_its_help
    with_sandbox do |env|
      status, out, err = run_config('config', env:)

      assert_equal [0, ''], [status, err]
      assert_includes out, 'Inspect the configuration that slipway resolved from flags, environment variables and ' \
                           "the configuration file.\n\nAvailable Commands:\n  view            Display the " \
                           "configuration in effect\n  path            Display the path of the configuration file\n"
      assert_includes out, "Usage:\n  slipway config COMMAND [flags]\n\nUse \"slipway config <command> --help\" for " \
                           'more information about a given command.'
    end
  end

  def test_subcommand_help_and_unknown_subcommands
    with_sandbox do |env|
      _, view_help, = run_config('config', 'view', '-h', env:)
      _, path_help, = run_config('config', 'path', '--help', env:)

      assert_includes view_help, "Display the configuration in effect.\n\nPrints every setting as YAML"
      assert_includes view_help, "Usage:\n  slipway config view [flags]\n"
      assert_includes path_help, "Examples:\n  # Print the path of the configuration file\n  slipway config path\n"
      assert_equal [2, '', "error: unknown command \"vew\" for \"slipway config\"\n\nDid you mean this?\n\tview\n\n" \
                           "Run 'slipway config --help' for usage.\n"], run_config('config', 'vew', env:)
    end
  end

  def test_subcommands_take_no_arguments
    with_sandbox do |env|
      assert_equal [2, '', "error: unexpected argument \"extra\"\nSee 'slipway config view --help' for usage.\n"],
                   run_config('config', 'view', 'extra', env:)
    end
  end

  private

  def default_path(env) = File.join(env['XDG_CONFIG_HOME'], 'slipway', 'config.yaml')

  # The production factory, so the view reflects the file, the variables and the flags of each run.
  def run_config(*argv, env:, **)
    registry = Slipway::CLI::Registry.new(program: Slipway::Commands::PROGRAM, version: Slipway::VERSION,
                                          description: Slipway::Commands::DESCRIPTION,
                                          globals: Slipway::CLI::Globals::ALL,
                                          commands: [Slipway::Commands::ConfigCommand.command(Slipway::Runtime.method(:build))])
    run_cli(*argv, env:, registry:, **)
  end

  def write_config(env, text)
    path = default_path(env)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, text)
    path
  end
end
