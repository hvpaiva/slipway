# frozen_string_literal: true

require 'test_helper'

class CompleterTest < Minitest::Test
  def setup
    @fixture = FixtureRegistry.new
    @completer = Slipway::CLI::Completer.new(@fixture.registry)
  end

  def test_verbs_carry_their_summaries_and_skip_hidden_commands
    candidates, directive = @completer.complete([''])

    assert_equal 4, directive
    assert_equal %w[get create explain config completion man help version].sort, candidates.map(&:first).sort
    assert_equal ['get', 'Display one or many resources'], candidates.first
    refute_includes candidates.map(&:first), 'raw'
    refute_includes candidates.map(&:first), '__complete'
  end

  def test_verb_prefix_filters_candidates
    assert_equal [['create', 'Create a resource'], ['config', 'Modify the configuration'],
                  ['completion', 'Output shell completion code for the specified shell (bash, zsh, fish)']],
                 @completer.complete(['c']).first
  end

  def test_group_subcommands
    assert_equal [['view', 'Print the effective configuration'], ['path', 'Print the configuration file path']],
                 @completer.complete(['config', '']).first
    assert_equal [['view', 'Print the effective configuration']], @completer.complete(%w[config v]).first
  end

  def test_positional_enum_has_no_descriptions
    assert_equal [%w[projects groups], 4], pairs(@completer.complete(['get', '']))
    assert_equal [['groups'], 4], pairs(@completer.complete(%w[get g]))
  end

  def test_dynamic_completer_drops_values_already_typed
    assert_equal [%w[alpha beta], 4], pairs(@completer.complete(['get', 'projects', '']))
    assert_equal [['beta'], 4], pairs(@completer.complete(['get', 'projects', 'alpha', '']))
  end

  def test_option_value_after_short_switch
    assert_equal [%w[table wide json yaml name], 4], pairs(@completer.complete(['get', 'projects', '-o', '']))
    assert_equal [['json'], 4], pairs(@completer.complete(%w[get projects -o j]))
  end

  def test_attached_short_value_is_consumed
    assert_equal [%w[alpha beta], 4], pairs(@completer.complete(['get', 'projects', '-ojson', '']))
  end

  def test_inline_long_value_keeps_the_flag_prefix
    assert_equal [['--output=json'], 4], pairs(@completer.complete(%w[get projects --output=j]))
    assert_equal [%w[--color=auto --color=always --color=never], 4], pairs(@completer.complete(%w[--color=]))
  end

  def test_lone_equals_word_separates_flag_and_value
    assert_equal [['json'], 4], pairs(@completer.complete(%w[get projects --output = j]))
    assert_equal [%w[table wide json yaml name], 4], pairs(@completer.complete(%w[get projects --output =]))
  end

  def test_optional_argument_option_never_waits_for_a_value
    candidates, = @completer.complete(['--color', ''])

    assert_includes candidates.map(&:first), 'get'
  end

  def test_switches_carry_descriptions
    candidates, = @completer.complete(%w[get projects --])

    assert_includes candidates, ['--output', 'Output format.']
    assert_includes candidates, ['--group', 'The group scope for this request.']
    refute_includes candidates.map(&:first), '-o'
    assert_includes @completer.complete(%w[get projects -]).first.map(&:first), '-o'
  end

  def test_globals_before_the_verb
    assert_equal [%w[projects groups], 4], pairs(@completer.complete(['-n', 'work', 'get', '']))
    assert_equal [%w[projects groups], 4], pairs(@completer.complete(['--config', 'x.yaml', 'get', '']))
  end

  def test_double_dash_makes_everything_positional
    assert_equal [%w[alpha beta], 4], pairs(@completer.complete(['get', 'projects', '--', '']))
    assert_equal [[], 4], @completer.complete(['get', 'projects', '--', '-'])
    assert_equal [['beta'], 4], pairs(@completer.complete(['get', 'projects', '--', 'alpha', '--', '']))
  end

  def test_unknown_subcommand_yields_only_the_directive
    assert_equal [[], 4], @completer.complete(['bogus', ''])
    assert_equal [[], 4], @completer.complete(['config', 'bogus', ''])
  end

  def test_files_directive_from_a_completer_returning_files
    completer = Slipway::CLI::Completer.new(files_registry)

    assert_equal [[], 0], completer.complete(['apply', '-f', ''])
    assert_equal [[], 0], completer.complete(%w[apply --filename=])
    assert_equal [[], 0], completer.complete(['apply', ''])
  end

  def test_a_no_space_answer_adds_the_no_space_directive
    assert_equal [%w[projects groups], 6], pairs(@completer.complete(['explain', '']))
    assert_equal [['projects'], 6], pairs(@completer.complete(%w[explain proj]))
    assert_equal [%w[projects.kind projects.spec], 6], pairs(@completer.complete(%w[explain projects.]))
    assert_equal [['projects.kind'], 4], pairs(@completer.complete(%w[explain projects.k]))
    assert_equal [['groups'], 4], pairs(@completer.complete(%w[explain g]))
  end

  def test_an_option_value_can_ask_for_no_space_too
    completer = Slipway::CLI::Completer.new(files_registry)

    assert_equal [['spec'], 6], pairs(completer.complete(['apply', '--field', 's']))
    assert_equal [['--field=spec'], 6], pairs(completer.complete(%w[apply --field=s]))
  end

  def test_hash_completer_supplies_descriptions
    completer = Slipway::CLI::Completer.new(files_registry)

    assert_equal [[['yaml', 'One YAML document'], ['json', 'One JSON object']], 4],
                 completer.complete(['apply', '--output', ''])
  end

  def test_a_completer_receives_the_positional_words_and_the_word_being_completed
    seen = []
    completer = Slipway::CLI::Completer.new(recording_registry(seen))

    completer.complete(%w[pick a b])
    completer.complete(%w[pick a --from wo])
    completer.complete(%w[pick --from=wo])
    completer.complete(%w[pick --from = wo])
    completer.complete(%w[pick --from =])

    assert_equal [[%w[a], 'b'], [%w[a], 'wo'], [[], 'wo'], [[], 'wo'], [[], '']], seen
  end

  def test_call_prints_candidates_then_the_directive
    status, out, err = @fixture.run('__complete', 'get', '')

    assert_equal 0, status
    assert_equal "projects\ngroups\n:4\n", out
    assert_empty err
    assert_equal "get\tDisplay one or many resources\n:4\n", @fixture.run('__complete', 'ge')[1]
    assert_equal "projects\n:6\n", @fixture.run('__complete', 'explain', 'proj')[1]
  end

  def test_call_prints_only_the_directive_when_completion_raises
    failing = Slipway::CLI::Registry.new(program: 'slipway', version: '0', description: 'x', globals: [],
                                         commands: [exploding_command])
    out = StringIO.new
    context = Slipway::CLI::Context.new(out:, err: StringIO.new)

    Slipway::CLI::Completer.new(failing).call(context, ['boom', ''], {})

    assert_equal ":4\n", out.string
  end

  private

  def pairs((candidates, directive)) = [candidates.map(&:first), directive]

  def files_registry
    apply = Slipway::CLI::Command.new(
      name: 'apply', summary: 'Apply a manifest',
      positionals: [Slipway::CLI::Positional.new(name: 'FILE', required: false,
                                                 completer: ->(_given, _current) { :files })],
      options: apply_options, handler: ->(*) {}
    )
    Slipway::CLI::Registry.new(program: 'slipway', version: '0', description: 'x', globals: [], commands: [apply])
  end

  def apply_options
    [
      Slipway::CLI::Option.new(long: 'filename', short: 'f', argument: 'FILE', description: 'Manifest.',
                               completer: ->(_given, _current) { Slipway::CLI::Completer::FILES }),
      Slipway::CLI::Option.new(long: 'output', argument: 'FORMAT', description: 'Output format.',
                               completer: lambda do |_given, _current|
                                 { 'yaml' => 'One YAML document', 'json' => 'One JSON object' }
                               end),
      Slipway::CLI::Option.new(long: 'field', argument: 'PATH', description: 'Field.',
                               completer: ->(_given, _current) { Slipway::CLI::Completer::NoSpace.new(%w[spec]) })
    ]
  end

  def recording_registry(seen)
    record = lambda do |given, current|
      seen << [given.dup, current]
      []
    end
    pick = Slipway::CLI::Command.new(
      name: 'pick', summary: 'Records what its completers receive',
      positionals: [Slipway::CLI::Positional.new(name: 'ITEM', variadic: true, completer: record)],
      options: [Slipway::CLI::Option.new(long: 'from', argument: 'WHERE', description: 'Where.', completer: record)],
      handler: ->(*) {}
    )
    Slipway::CLI::Registry.new(program: 'slipway', version: '0', description: 'x', globals: [], commands: [pick])
  end

  def exploding_command
    Slipway::CLI::Command.new(
      name: 'boom', summary: 'Fails while completing',
      positionals: [Slipway::CLI::Positional.new(name: 'X', completer: ->(_given, _current) { raise 'no' })], handler: ->(*) {}
    )
  end
end
