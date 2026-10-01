# frozen_string_literal: true

require 'test_helper'

class CommandsRegistryTest < Minitest::Test
  include CommandsHelper

  LIB = File.expand_path('../../../lib', __dir__)
  PATH_DIRECTIVES = { 'DIR' => 16, 'FILE' => 0, 'PATH' => 0 }.freeze

  def test_registry_lists_the_verbs_in_order_before_the_builtins
    registry = Slipway::Commands.registry(->(_context, _opts) { raise 'unused' })

    assert_equal %w[get describe create apply delete edit label explain fetch diff sync rollout config api-resources
                    help version completion man __complete],
                 registry.root.subcommands.map(&:name)
    assert_equal ['slipway', Slipway::VERSION, 'A kubectl-style registry of the git repositories on your machine'],
                 [registry.program, registry.version, registry.description]
    assert_equal Slipway::CLI::Globals::ALL.map(&:long), registry.globals.map(&:long)
    assert_equal 'Resource types: projects (project, proj) and groups (group). Type words are case-insensitive.',
                 registry.root.description.lines.last.strip
  end

  def test_verbs_sit_in_their_help_sections
    registry = Slipway::Commands.registry(->(_context, _opts) { raise 'unused' })
    sections = registry.root.visible_subcommands.group_by(&:section).transform_values { |list| list.map(&:name) }

    assert_equal ['Basic Commands', 'Repository Commands', 'Settings Commands', 'Other Commands'],
                 registry.root.sections.map(&:first)
    assert_equal %w[get describe create apply delete edit label explain], sections.fetch('Basic Commands')
    assert_equal %w[fetch diff sync rollout], sections.fetch('Repository Commands')
    assert_equal %w[config completion man], sections.fetch('Settings Commands')
    assert_equal %w[api-resources help version], sections.fetch('Other Commands')
  end

  def test_every_command_class_is_reachable_from_the_verbs
    commands = Slipway::Commands::VERBS.map { it.command(->(_context, _opts) { raise 'unused' }) }
    handlers = commands.flat_map { handler_classes(it) }
    shipped = command_classes(Slipway::Commands::Base).select { it.name && defined_in_lib?(it.name) }

    assert_empty(shipped.reject { handlers.include?(it) }.map(&:name))
    assert_operator shipped.size, :>, 8
    assert_includes handlers, Slipway::Commands::Config::Path
  end

  def test_the_kinds_a_verb_acts_on_follow_its_arguments
    verbs = Slipway::Commands::VERBS.flat_map { leaves(it.command(->(_context, _opts) { raise 'unused' })) }
    typed, rest = verbs.partition { |verb| verb.positionals.any? { it.name == 'TYPE' } }
    named, bare = rest.partition { it.positionals.any? }
    every = %w[projects groups]

    assert_equal %w[get describe create delete edit label explain].to_h { [it, every] }, kinds_by_name(typed)
    assert_equal %w[fetch diff sync history undo unpin pause resume].to_h { [it, %w[projects]] }, kinds_by_name(named)
    assert_equal({ 'apply' => every, 'view' => [], 'path' => [], 'api-resources' => [] }, kinds_by_name(bare))
  end

  def test_every_option_that_takes_a_path_completes_file_or_directory_names
    registry = Slipway::Commands.registry(->(_context, _opts) { raise 'unused' })
    completer = Slipway::CLI::Completer.new(registry)
    requests = path_requests(registry.root, [], registry.globals)

    assert_includes requests, [['create', '--path', ''], 16]
    assert_includes requests, [['man', '--install='], 16]
    assert_includes requests, [['--config', ''], 0]
    assert_empty(requests.reject { |words, directive| completer.complete(words) == [[], directive] }
                         .map { |words, _| words.join(' ') })
  end

  def test_command_classes_reach_every_descendant_but_abstract_bases
    base = Class.new
    abstract = Class.new(base)
    concrete = Class.new(abstract) { def self.command(_factory) = nil }
    inherited = Class.new(concrete)

    assert_equal [concrete, inherited], command_classes(base)
  end

  def test_run_dispatches_through_the_runtime_factory
    with_sandbox do |env|
      runtime = sandbox_runtime(env)
      register(runtime, 'hldr')

      assert_equal [0, "NAME   BRANCH   STATUS   FETCHED   AGE\nhldr   main     Clean    <never>   3h\n", ''],
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

      assert_equal "\e[37mhldr\e[0m   \e[36mmain\e[0m   \e[32mClean\e[0m   \e[90;3m<never>\e[0m   \e[37m3h\e[0m\n",
                   dark
      assert_equal "\e[30mhldr\e[0m   \e[34mmain\e[0m   \e[32mClean\e[0m   \e[90;3m<never>\e[0m   \e[30m3h\e[0m\n",
                   light
      assert_equal "hldr   main   Clean   <never>   3h\n", plain
    end
  end

  def test_run_reports_a_broken_config_file_once_with_exit_one
    with_sandbox do |env|
      path = write_config(env, "colour: always\n")

      status, out, err = run_cli('get', 'projects', env:)

      assert_equal [1, ''], [status, out]
      assert_equal "error: #{path}: unknown key \"colour\" (known keys: color, editor, group, networkTimeout, " \
                   "parallel, protocols, theme)\n", err
    end
  end

  def test_run_uses_the_production_factory_by_default
    with_sandbox do |env|
      assert_equal [0, '', "No resources found in default group.\n"], run_cli('get', 'projects', env:)
      assert_equal [0, '', "No resources found.\n"], run_cli('get', 'groups', env:)
    end
  end

  private

  def defined_in_lib?(name) = Object.const_source_location(name)&.first&.start_with?("#{LIB}/")

  def descendants(klass) = klass.subclasses.flat_map { [it, *descendants(it)] }

  # A class without `self.command` is an abstract base, never a registry entry.
  def command_classes(base) = descendants(base).select { it.respond_to?(:command) }

  def handler_classes(command) = [command.handler.class, *command.subcommands.flat_map { handler_classes(it) }]

  def leaves(command) = command.group? ? command.subcommands.flat_map { leaves(it) } : [command]

  def kinds_by_name(commands) = commands.to_h { [it.name, it.handler.kinds.map(&:plural)] }

  # The words that ask for the value of every option taking a path, separate and attached; an
  # optional-argument option takes its value only attached.
  def path_requests(command, path, globals)
    options = (globals + command.options).select { PATH_DIRECTIVES.key?(it.argument) }
    requests = options.flat_map do |option|
      attached = [*path, "--#{option.long}="]
      words = option.optional ? [attached] : [[*path, "--#{option.long}", ''], attached]
      words.map { [it, PATH_DIRECTIVES.fetch(option.argument)] }
    end
    requests + command.subcommands.flat_map { path_requests(it, [*path, it.name], globals) }
  end

  def write_config(env, text)
    path = File.join(env['XDG_CONFIG_HOME'], 'slipway', 'config.yaml')
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, text)
    path
  end
end
