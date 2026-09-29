# frozen_string_literal: true

require 'test_helper'

class BuiltinsTest < Minitest::Test
  def setup
    @fixture = FixtureRegistry.new
  end

  def test_all_registers_the_four_builtins_in_their_sections
    builtins = Slipway::CLI::Builtins.all(program: 'slipway', version: '0.1.0', resolve: -> { @fixture.registry })

    assert_equal %w[help version completion __complete], builtins.map(&:name)
    assert_equal ['Other Commands', 'Other Commands', 'Settings Commands'], builtins.first(3).map(&:section)
    assert_predicate builtins.last, :hidden
    assert_predicate builtins.last, :raw
  end

  def test_help_without_arguments_renders_the_root_page
    assert_equal @fixture.run('--help'), @fixture.run('help')
  end

  def test_help_with_a_path_renders_the_same_page_as_the_help_flag
    assert_equal @fixture.run('config', 'view', '--help'), @fixture.run('help', 'config', 'view')
    assert_equal @fixture.run('get', '--help'), @fixture.run('help', 'get')
  end

  def test_help_for_an_unknown_command_is_a_usage_error
    status, out, err = @fixture.run('help', 'bogus')

    assert_equal 2, status
    assert_empty out
    assert_equal "error: unknown command \"bogus\" for \"slipway\"\nRun 'slipway --help' for usage.\n", err
  end

  def test_version_prints_program_ruby_and_platform
    status, out, err = @fixture.run('version')

    assert_equal 0, status
    assert_match(/\Aslipway 0\.1\.0 \(ruby \d+\.\d+\.\d+\) \[[\w-]+\]\n\z/, out)
    assert_equal "slipway 0.1.0 (ruby #{RUBY_VERSION}) [#{Gem::Platform.local}]\n", out
    assert_empty err
  end

  def test_completion_prints_a_script_for_each_shell
    _, bash, = @fixture.run('completion', 'bash')
    _, zsh, = @fixture.run('completion', 'zsh')
    _, fish, = @fixture.run('completion', 'fish')

    assert_includes bash, 'complete -o default -F _slipway_complete slipway'
    assert_includes bash, 'slipway __complete "${words[@]}"'
    assert_equal '#compdef slipway', zsh.lines.first.chomp
    assert_includes fish, "complete -c slipway -f -a '(__slipway_complete)'"
  end

  def test_completion_rejects_unknown_and_missing_shells
    status, _, unknown = @fixture.run('completion', 'powershell')
    _, _, missing = @fixture.run('completion')

    assert_equal 2, status
    assert_equal "error: invalid argument \"powershell\" for SHELL: must be one of bash, zsh, fish\n" \
                 "See 'slipway completion --help' for usage.\n", unknown
    assert_equal "error: missing required argument \"SHELL\"\nSee 'slipway completion --help' for usage.\n", missing
  end

  def test_complete_prints_one_candidate_per_line
    assert_equal "projects\ngroups\n", @fixture.run('__complete', 'get', '')[1]
    assert_equal "alpha\nbeta\n", @fixture.run('__complete', 'get', 'projects', '')[1]
    assert_equal "beta\n", @fixture.run('__complete', 'get', 'projects', 'alpha', 'b')[1]
    assert_equal "table\nwide\njson\nyaml\nname\n", @fixture.run('__complete', 'get', 'projects', '-o', '')[1]
  end

  def test_complete_lists_visible_commands_only
    status, out, err = @fixture.run('__complete', '')

    assert_equal 0, status
    assert_equal %w[get ls create config help version completion], out.split("\n")
    assert_empty err
  end
end
