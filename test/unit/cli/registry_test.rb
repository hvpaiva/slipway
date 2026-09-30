# frozen_string_literal: true

require 'test_helper'

class RegistryTest < Minitest::Test
  def setup
    @fixture = FixtureRegistry.new
    @registry = @fixture.registry
  end

  def test_resolve_walks_nested_groups
    command, path = @registry.resolve(%w[config view])

    assert_equal 'view', command.name
    assert_equal %w[config view], path
  end

  def test_resolve_accepts_aliases
    command, path = @registry.resolve(%w[ls])

    assert_equal 'get', command.name
    assert_equal %w[ls], path
  end

  def test_resolve_rejects_an_unknown_word_with_suggestions_and_the_run_hint
    error = assert_raises(Slipway::CLI::UsageError) { @registry.resolve(%w[gte]) }

    assert_equal 2, error.exit_status
    assert_equal "unknown command \"gte\" for \"slipway\"\n\nDid you mean this?\n\tget\n\n", error.message
    assert_equal "Run 'slipway --help' for usage.", error.hint
  end

  def test_unknown_command_inside_a_group_names_the_path
    message = @registry.unknown_command('vew', %w[config])

    assert_includes message, 'unknown command "vew" for "slipway config"'
    assert_includes message, "\tview"
  end

  def test_unknown_command_without_a_near_miss_has_no_suggestion_block
    assert_equal 'unknown command "zzz" for "slipway"', @registry.unknown_command('zzz', [])
  end

  def test_unknown_option_suggests_long_switches_only
    options = @fixture.command('get').options

    assert_equal "unknown flag: --no-headers\n\nDid you mean this?\n\t--no-headers\n\n",
                 @registry.unknown_option('--no-headers=1', options)
    assert_includes @registry.unknown_option('--no-header', options), "\t--no-headers"
    assert_equal 'unknown flag: -x', @registry.unknown_option('-x', options)
    assert_equal 'unknown flag: --bogus', @registry.unknown_option('--bogus', options)
  end

  def test_hints_follow_kubectl_wording
    assert_equal "See 'slipway get --help' for usage.", @registry.help_hint(%w[get])
    assert_equal "See 'slipway --help' for usage.", @registry.help_hint([])
    assert_equal "Run 'slipway config --help' for usage.", @registry.run_hint(%w[config])
  end

  def test_sections_follow_kubectl_order_and_leave_hidden_commands_out
    sections = @registry.root.sections

    assert_equal ['Basic Commands', 'Settings Commands', 'Other Commands'], sections.map(&:first)
    assert_equal [%w[get create], %w[config completion man], %w[help version]],
                 sections.map { |_, commands| commands.map(&:name) }.to_a
  end

  def test_long_description_replaces_the_summary_on_the_root_command_only
    registry = Slipway::CLI::Registry.new(program: 'x', version: '0', description: 'Short.', globals: [], commands: [],
                                          long_description: "Short.\n\n Long.", builtins: false)

    assert_equal "Short.\n\n Long.", registry.root.description
    assert_equal 'Short.', registry.root.summary
    assert_equal FixtureRegistry::DESCRIPTION, @registry.root.description
  end

  def test_description_parts_spell_the_enum_the_default_and_the_requirement
    output, no_headers = @registry.resolve(%w[get]).first.options
    path = @registry.resolve(%w[create]).first.options.first

    assert_equal ['Output format.', 'One of: table, wide, json, yaml, name.', '(default "table")'],
                 output.description_parts
    assert_equal ["When using the default output format, don't print headers."], no_headers.description_parts
    assert_equal ['Directory of the repository.', '(required)'], path.description_parts
  end

  def test_builtins_can_be_left_out
    registry = Slipway::CLI::Registry.new(program: 'x', version: '0', description: 'd', globals: [], commands: [],
                                          builtins: false)

    assert_empty registry.root.subcommands
  end
end

class SuggestTest < Minitest::Test
  def test_similar_uses_distance_two_or_a_shared_prefix
    dictionary = %w[get set describe create]

    assert_equal %w[get], Slipway::CLI::Suggest.similar('gte', dictionary)
    assert_equal %w[get set], Slipway::CLI::Suggest.similar('gt', dictionary)
    assert_equal %w[describe], Slipway::CLI::Suggest.similar('desc', dictionary)
    assert_equal %w[create], Slipway::CLI::Suggest.similar('created', dictionary)
    assert_empty Slipway::CLI::Suggest.similar('zzzzzz', dictionary)
  end
end

class OptionTest < Minitest::Test
  def test_key_turns_dashes_into_underscores
    assert_equal :no_headers, option(long: 'no-headers').key
  end

  def test_switches_and_specs_for_a_flag
    flag = option(long: 'no-headers')

    assert_predicate flag, :flag?
    assert_equal %w[--no-headers], flag.switches
    assert_equal %w[--no-headers], flag.switch_spec
    assert_equal '--no-headers', flag.label
  end

  def test_switches_and_specs_for_a_valued_option
    valued = option(long: 'output', short: 'o', argument: 'FORMAT')

    refute_predicate valued, :flag?
    assert_equal %w[-o --output], valued.switches
    assert_equal ['-o', '--output FORMAT'], valued.switch_spec
    assert_equal '-o, --output FORMAT', valued.label
  end

  def test_optional_argument_is_spelled_with_brackets
    color = option(long: 'color', argument: 'WHEN', optional: true, implicit: 'always')

    assert_equal ['--color[=WHEN]'], color.switch_spec
    assert_equal '--color[=WHEN]', color.label
  end

  def test_accept_folds_one_occurrence_into_the_stored_value
    color = option(long: 'color', argument: 'WHEN', optional: true, implicit: 'always')

    assert option(long: 'no-headers').accept(nil, nil)
    assert_equal 'always', color.accept(nil, nil)
    assert_equal 'never', color.accept(nil, 'never')
    assert_equal %w[a=b c=d], option(long: 'label', argument: 'KV', repeatable: true).accept(['a=b'], 'c=d')
    assert_equal 'json', option(long: 'output', argument: 'FORMAT').accept('table', 'json')
  end

  def test_candidates_come_from_the_enum_or_the_completer
    assert_equal %w[a b], option(long: 'x', argument: 'V', enum: %w[a b]).candidates
    echo = option(long: 'x', argument: 'V', completer: ->(given, current) { [*given, current] })

    assert_equal %w[given cur], echo.candidates(%w[given], 'cur')
    assert_equal [''], echo.candidates
    assert_empty option(long: 'x', argument: 'V').candidates
  end

  private

  def option(**attributes) = Slipway::CLI::Option.new(description: 'd', **attributes)
end

class PositionalTest < Minitest::Test
  def test_usage_marks_optional_and_variadic_arguments
    assert_equal 'TYPE', Slipway::CLI::Positional.new(name: 'TYPE').usage
    assert_equal '[NAME...]', Slipway::CLI::Positional.new(name: 'NAME', required: false, variadic: true).usage
    assert_equal 'FILE...', Slipway::CLI::Positional.new(name: 'FILE', variadic: true).usage
  end
end

class CommandTest < Minitest::Test
  def setup
    @fixture = FixtureRegistry.new
  end

  def test_arity_comes_from_the_positionals
    get = @fixture.command('get')
    create = @fixture.command('create')

    assert_equal 1, get.min_args
    assert_nil get.max_args
    assert_equal 2, create.min_args
    assert_equal 2, create.max_args
  end

  def test_positional_at_repeats_the_variadic_tail
    get = @fixture.command('get')

    assert_equal 'TYPE', get.positional_at(0).name
    assert_equal 'NAME', get.positional_at(1).name
    assert_equal 'NAME', get.positional_at(5).name
    assert_nil @fixture.command('create').positional_at(2)
  end

  def test_groups_hide_hidden_subcommands_and_use_command_as_usage
    root = @fixture.registry.root

    assert_predicate root, :group?
    assert_equal 'COMMAND', root.usage_args
    refute_includes root.visible_subcommands.map(&:name), 'raw'
    assert_equal 'TYPE [NAME...]', @fixture.command('get').usage_args
  end

  def test_description_defaults_to_the_summary
    command = Slipway::CLI::Command.new(name: 'x', summary: 'Do x')

    assert_equal 'Do x', command.description
    assert_equal 'Available Commands', command.section
  end
end
