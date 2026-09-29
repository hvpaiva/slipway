# frozen_string_literal: true

require 'test_helper'

class BaseTest < Minitest::Test
  include CommandsHelper

  # A verb that reports what it received and prints one result line.
  class Echo < Slipway::Commands::Base
    def self.command(factory)
      Slipway::CLI::Command.new(name: 'echo', summary: 'Echo', section: 'Basic Commands',
                                positionals: [Slipway::Commands::Options::TYPE,
                                              Slipway::Commands::Options.name_positional(factory, required: true)],
                                options: [Slipway::Commands::Options::DRY_RUN], handler: new(factory))
    end

    def run(runtime, context, args, opts)
      kind = scope(runtime, context, opts).kind(args.first)
      result_line(context, kind, args[1], 'created', :create_created, dry_run: opts[:dry_run] == 'client')
    end
  end

  def test_call_builds_the_runtime_through_the_factory_and_prints_the_result_line
    with_sandbox do |env|
      runtime = sandbox_runtime(env)
      status, out, err = run_commands('echo', 'project', 'hldr', runtime:, commands: [Echo])

      assert_equal [0, "project/hldr created\n", ''], [status, out, err]
    end
  end

  def test_result_line_paints_the_verb_and_the_dry_run_suffix
    with_sandbox do |env|
      runtime = sandbox_runtime(env)
      _, plain, = run_commands('echo', 'groups', 'work', '--dry-run', 'client', runtime:, commands: [Echo])
      _, painted, = run_commands('echo', 'groups', 'work', '--dry-run=client', '--color', runtime:, commands: [Echo])

      assert_equal "group/work created (dry run)\n", plain
      assert_equal "group/work \e[32mcreated\e[0m \e[36m(dry run)\e[0m\n", painted
    end
  end

  def test_the_factory_receives_the_context_and_the_parsed_options
    received = []
    factory = lambda do |context, opts|
      received << [context, opts]
      raise Slipway::Error, 'stop here'
    end
    registry = Slipway::CLI::Registry.new(program: 'slipway', version: '0', description: 'd',
                                          globals: Slipway::CLI::Globals::ALL, commands: [Echo.command(factory)])

    status, _, err = run_cli('-n', 'work', 'echo', 'projects', 'x', registry:)

    assert_equal [1, "error: stop here\n"], [status, err]
    assert_equal 'work', received.fetch(0).fetch(1).fetch(:group)
    assert_instance_of Slipway::CLI::Context, received.fetch(0).fetch(0)
  end

  def test_shared_options_carry_kubectl_keys_defaults_and_enums
    options = Slipway::Commands::Options

    assert_equal [:output, 'o', 'table', Slipway::Output::FORMATS],
                 [options::OUTPUT.key, options::OUTPUT.short, options::OUTPUT.default, options::OUTPUT.enum]
    assert_equal %i[selector all_groups no_headers show_labels dry_run],
                 [options::SELECTOR, options::ALL_GROUPS, options::NO_HEADERS, options::SHOW_LABELS,
                  options::DRY_RUN].map(&:key)
    assert_equal %w[A l], [options::ALL_GROUPS.short, options::SELECTOR.short]
    assert_equal [%w[none client], 'none'], [options::DRY_RUN.enum, options::DRY_RUN.default]
    assert_predicate options::ALL_GROUPS, :flag?
  end

  def test_type_positional_completes_the_plural_type_words_with_descriptions
    candidates = Slipway::Commands::Options::TYPE.candidates([])

    assert_equal Slipway::Resources::KINDS.map(&:plural), candidates.keys
    assert_equal ['Registered git repositories', 'Namespaces that hold projects'], candidates.values
    assert_nil Slipway::Commands::Options::TYPE.enum
  end

  def test_name_positional_completes_from_the_store_across_groups
    with_sandbox do |env|
      runtime = sandbox_runtime(env)
      register_group(runtime, 'work')
      register(runtime, 'hldr')
      register(runtime, 'job', group: 'work')
      positional = Slipway::Commands::Options.name_positional(->(_context, _opts) { runtime }, variadic: false,
                                                                                               required: true)

      assert_equal %w[hldr job], positional.candidates(%w[projects])
      assert_equal %w[default work], positional.candidates(%w[groups])
      assert_empty positional.candidates(%w[pods])
      assert_empty positional.candidates([])
      assert_equal [false, true], [positional.variadic, positional.required]
    end
  end

  def test_name_positional_builds_the_runtime_lazily_from_the_process_context
    with_sandbox do |env|
      runtime = sandbox_runtime(env)
      built = []
      factory = lambda do |context, opts|
        built << [context, opts]
        runtime
      end
      positional = Slipway::Commands::Options.name_positional(factory)

      assert_empty built
      assert_equal [], positional.candidates(%w[projects])
      assert_equal [{}], built.map(&:last)
      assert_instance_of Slipway::CLI::Context, built.fetch(0).fetch(0)
    end
  end

  def test_name_positional_hides_a_failing_factory
    positional = Slipway::Commands::Options.name_positional(->(_context, _opts) { raise 'boom' })

    assert_empty positional.candidates(%w[projects])
    assert_equal [true, false], [positional.variadic, positional.required]
  end
end
