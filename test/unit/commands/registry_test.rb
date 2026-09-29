# frozen_string_literal: true

require 'test_helper'

# The full registry and the wiring of Slipway.run around it.
class CommandsRegistryTest < Minitest::Test
  include CommandsHelper

  def test_registry_lists_the_verbs_in_order_before_the_builtins
    registry = Slipway::Commands.registry(->(_context, _opts) { raise 'unused' })

    assert_equal %w[get describe create apply delete edit label config help version completion man __complete],
                 registry.root.subcommands.map(&:name)
    assert_equal ['slipway', Slipway::VERSION, 'A kubectl-style registry for the git repositories on your machine'],
                 [registry.program, registry.version, registry.description]
    assert_equal Slipway::CLI::Globals::ALL.map(&:long), registry.globals.map(&:long)
    assert_equal 'Resource types: projects (project, proj) and groups (group). Type words are case-insensitive.',
                 registry.root.description.lines.last.strip
  end

  def test_verbs_sit_in_their_help_sections
    registry = Slipway::Commands.registry(->(_context, _opts) { raise 'unused' })
    sections = registry.root.visible_subcommands.group_by(&:section).transform_values { |list| list.map(&:name) }

    assert_equal %w[get describe create apply delete edit label], sections.fetch('Basic Commands')
    assert_equal %w[config completion man], sections.fetch('Settings Commands')
    assert_equal %w[help version], sections.fetch('Other Commands')
  end

  def test_run_dispatches_through_the_runtime_factory
    with_sandbox do |env|
      runtime = sandbox_runtime(env)
      register(runtime, 'hldr')

      assert_equal [0, "NAME   BRANCH   STATUS   AGE\nhldr   main     Clean    3h\n", ''],
                   run_cli('get', 'projects', env:, runtime:)
      assert_equal [0, '', "No resources found in work group.\n"],
                   run_cli('get', 'projects', '-n', 'work', env:, runtime:)
    end
  end

  def test_run_takes_color_and_theme_defaults_from_the_config_file
    with_sandbox do |env|
      runtime = sandbox_runtime(env)
      register(runtime, 'hldr')
      other = File.join(env['HOME'], 'light.yaml')
      File.write(other, "color: always\ntheme: light\n")
      write_config(env, "color: always\n")

      _, dark, = run_cli('get', 'projects', '--no-headers', env:, runtime:)
      _, light, = run_cli('get', 'projects', '--no-headers', "--config=#{other}", env:, runtime:)
      _, plain, = run_cli('get', 'projects', '--no-headers', '--color=never', env:, runtime:)

      assert_equal "\e[37mhldr\e[0m   \e[36mmain\e[0m   \e[32mClean\e[0m   \e[36m3h\e[0m\n", dark
      assert_equal "\e[30mhldr\e[0m   \e[34mmain\e[0m   \e[32mClean\e[0m   \e[34m3h\e[0m\n", light
      assert_equal "hldr   main   Clean   3h\n", plain
    end
  end

  def test_run_reports_a_broken_config_file_once_with_exit_one
    with_sandbox do |env|
      path = write_config(env, "colour: always\n")

      status, out, err = run_cli('get', 'projects', env:)

      assert_equal [1, ''], [status, out]
      assert_equal "error: #{path}: unknown key \"colour\" (known keys: color, editor, group, theme)\n", err
    end
  end

  def test_run_uses_the_production_factory_by_default
    with_sandbox do |env|
      assert_equal [0, '', "No resources found in default group.\n"], run_cli('get', 'projects', env:)
      assert_equal [0, '', "No resources found.\n"], run_cli('get', 'groups', env:)
    end
  end

  private

  def write_config(env, text)
    path = File.join(env['XDG_CONFIG_HOME'], 'slipway', 'config.yaml')
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, text)
    path
  end
end
