# frozen_string_literal: true

require 'test_helper'

class RunnerTest < Minitest::Test
  # A stream whose reader has gone away.
  class BrokenPipe < StringIO
    def write(*) = raise(Errno::EPIPE)
  end

  def setup
    @fixture = FixtureRegistry.new
  end

  def test_empty_invocation_prints_root_help_and_succeeds
    status, out, err = @fixture.run

    assert_equal 0, status
    assert_equal FixtureRegistry::DESCRIPTION, out.lines.first.chomp
    assert_includes out, "Basic Commands:\n"
    assert_empty err
    assert_empty @fixture.calls
  end

  def test_help_flags_render_the_command_page
    long = @fixture.run('get', '--help')
    short = @fixture.run('-h', 'get')

    assert_equal [0, ''], [long[0], long[2]]
    assert_equal long, short
    assert_includes long[1], "Usage:\n  slipway get TYPE [NAME...] [flags]\n"
    assert_empty @fixture.calls
  end

  def test_version_flags_print_the_version_line
    status, out, err = @fixture.run('--version')

    assert_equal 0, status
    assert_equal "slipway 0.1.0 (ruby #{RUBY_VERSION}) [#{Gem::Platform.local}]\n", out
    assert_empty err
    assert_equal out, @fixture.run('-V')[1]
  end

  def test_group_without_subcommand_prints_its_help
    status, out, = @fixture.run('config')

    assert_equal 0, status
    assert_includes out, "Available Commands:\n  view "
    assert_empty @fixture.calls
  end

  def test_success_dispatches_args_and_defaulted_opts_to_the_handler
    status, out, err = @fixture.run('get', 'projects', 'alpha', '-o', 'json')
    call = @fixture.calls.fetch(0)

    assert_equal [0, '', ''], [status, out, err]
    assert_equal ['get', %w[projects alpha]], [call.name, call.args]
    assert_equal({ output: 'json', no_headers: nil, selector: nil, color: 'auto', group: nil, config: nil, help: nil,
                   version: nil }, call.opts)
    assert_predicate call.opts, :frozen?
  end

  def test_global_flags_are_accepted_before_between_and_after
    @fixture.run('-n', 'work', 'get', 'projects')
    @fixture.run('get', 'projects', '-n', 'work')
    @fixture.run('config', '-n', 'work', 'view')

    assert_equal(%w[work work work], @fixture.calls.map { it.opts[:group] })
    assert_equal ['get', 'get', 'config view'], @fixture.calls.map(&:name)
  end

  def test_double_dash_passes_dash_words_as_positionals
    status, = @fixture.run('get', 'projects', '--', '-weird-name')

    assert_equal 0, status
    assert_equal %w[projects -weird-name], @fixture.calls.fetch(0).args
  end

  def test_unknown_command_is_a_usage_error_with_the_run_hint
    status, out, err = @fixture.run('gte', 'projects')

    assert_equal 2, status
    assert_empty out
    assert_equal "error: unknown command \"gte\" for \"slipway\"\n\nDid you mean this?\n\tget\n\n" \
                 "Run 'slipway --help' for usage.\n", err
  end

  def test_unknown_flag_is_a_usage_error_with_the_see_hint
    status, out, err = @fixture.run('get', 'projects', '--bogus')

    assert_equal 2, status
    assert_empty out
    assert_equal "error: unknown flag: --bogus\nSee 'slipway get --help' for usage.\n", err
  end

  def test_parse_and_validation_errors_share_the_see_hint
    _, _, missing = @fixture.run('get', 'projects', '-o')
    _, _, arity = @fixture.run('get')
    status, _, enum = @fixture.run('get', 'projects', '-o', 'xml')

    assert_equal "error: missing argument: -o\nSee 'slipway get --help' for usage.\n", missing
    assert_equal "error: missing required argument \"TYPE\"\nSee 'slipway get --help' for usage.\n", arity
    assert_equal 2, status
    assert_equal 'error: invalid argument "xml" for "-o, --output FORMAT": must be one of table, wide, json, ' \
                 "yaml, name\nSee 'slipway get --help' for usage.\n", enum
  end

  def test_domain_errors_exit_one_without_a_hint
    @fixture.failure = Slipway::Error.new('projects "gamma" not found')
    status, out, err = @fixture.run('get', 'projects', 'gamma')

    assert_equal 1, status
    assert_empty out
    assert_equal "error: projects \"gamma\" not found\n", err
  end

  def test_usage_errors_from_handlers_get_the_command_hint_when_they_have_none
    @fixture.failure = Slipway::CLI::UsageError.new('invalid selector "a=="')
    status, _, err = @fixture.run('get', 'projects', '-l', 'a==')

    assert_equal 2, status
    assert_equal "error: invalid selector \"a==\"\nSee 'slipway get --help' for usage.\n", err
  end

  def test_usage_errors_from_handlers_keep_their_own_hint
    @fixture.failure = Slipway::CLI::UsageError.new('nope', hint: 'Try again.')
    _, _, err = @fixture.run('config', 'view')

    assert_equal "error: nope\nTry again.\n", err
  end

  def test_unexpected_errors_exit_one_with_the_message_only
    @fixture.failure = RuntimeError.new('kaboom')
    status, out, err = @fixture.run('get', 'projects')

    assert_equal 1, status
    assert_empty out
    assert_equal "error: kaboom\n", err
  end

  def test_unexpected_errors_add_class_and_backtrace_when_debugging
    @fixture.failure = RuntimeError.new('kaboom')
    status, _, err = @fixture.run('get', 'projects', env: { 'SLIPWAY_DEBUG' => '1' })

    assert_equal 1, status
    assert_equal ['error: kaboom', 'RuntimeError'], err.lines(chomp: true).first(2)
    assert_match(/\A {4}.*fixture_registry\.rb:\d+/, err.lines[2])
  end

  def test_empty_debug_variable_does_not_count
    @fixture.failure = RuntimeError.new('kaboom')
    _, _, err = @fixture.run('get', 'projects', env: { 'SLIPWAY_DEBUG' => '' })

    assert_equal "error: kaboom\n", err
  end

  def test_interrupt_exits_130_with_a_bare_newline
    @fixture.failure = Interrupt
    status, out, err = @fixture.run('get', 'projects')

    assert_equal 130, status
    assert_empty out
    assert_equal "\n", err
  end

  def test_broken_pipe_exits_zero_silently
    @fixture.failure = Errno::EPIPE
    status, out, err = @fixture.run('get', 'projects')

    assert_equal 0, status
    assert_empty out
    assert_empty err
  end

  def test_broken_pipe_while_reporting_an_error_exits_zero
    @fixture.failure = Slipway::Error.new('boom')
    context = Slipway::CLI::Context.new(out: StringIO.new, err: BrokenPipe.new)

    assert_equal 0, Slipway::CLI::Runner.new(@fixture.registry, context).run(%w[get projects])
  end

  def test_unknown_subcommand_inside_a_group_points_at_the_group_help
    status, out, err = @fixture.run('config', 'vew')

    assert_equal 2, status
    assert_empty out
    assert_equal "error: unknown command \"vew\" for \"slipway config\"\n\nDid you mean this?\n\tview\n\n" \
                 "Run 'slipway config --help' for usage.\n", err
  end

  def test_raw_commands_receive_argv_untouched
    status, = @fixture.run('raw', '-o', '--bogus', '--', 'x')
    call = @fixture.calls.fetch(0)

    assert_equal 0, status
    assert_equal %w[-o --bogus -- x], call.args
    assert_empty call.opts
  end

  def test_color_is_decided_per_stream
    @fixture.failure = Slipway::Error.new('boom')
    _, _, plain_err = @fixture.run('get', 'projects', tty: true, err_tty: false)
    _, _, colored_err = @fixture.run('get', 'projects', tty: false, err_tty: true)

    assert_equal "error: boom\n", plain_err
    assert_equal "\e[31merror:\e[0m boom\n", colored_err
    assert_equal([true, false], @fixture.calls.map { it.context.color? })
  end

  def test_color_flag_beats_environment_and_given_default
    @fixture.run('--color=never', 'get', 'projects', env: { 'SLIPWAY_COLOR' => 'always' }, color: 'always')
    @fixture.run('get', 'projects', '--color', env: { 'SLIPWAY_COLOR' => 'never' }, color: 'never')

    assert_equal([false, true], @fixture.calls.map { it.context.color? })
    assert_equal(%w[never always], @fixture.calls.map { it.opts[:color] })
  end

  def test_color_environment_beats_the_given_default_which_beats_auto
    @fixture.run('get', 'projects', env: { 'SLIPWAY_COLOR' => 'always' }, color: 'never')
    @fixture.run('get', 'projects', env: { 'SLIPWAY_COLOR' => '' }, color: 'always')
    @fixture.run('get', 'projects', tty: true)
    @fixture.run('get', 'projects', tty: true, env: { 'NO_COLOR' => '1' })

    assert_equal([true, true, true, false], @fixture.calls.map { it.context.color? })
  end

  def test_color_flag_placed_after_the_verb_colors_the_error_that_follows
    _, _, err = @fixture.run('get', 'projects', '--color=always', '--bogus')

    assert_equal "\e[31merror:\e[0m unknown flag: --bogus\nSee 'slipway get --help' for usage.\n", err
  end

  def test_theme_comes_from_the_environment_then_the_given_default
    @fixture.run('get', 'projects', env: { 'SLIPWAY_THEME' => 'light' }, theme: 'dark')
    @fixture.run('get', 'projects', theme: 'light')
    @fixture.run('get', 'projects')

    assert_equal(%w[light light dark], @fixture.calls.map { it.context.style.theme.name })
  end

  def test_unknown_color_mode_in_the_environment_is_reported_as_an_error
    status, out, err = @fixture.run('get', 'projects', env: { 'SLIPWAY_COLOR' => 'blue' })

    assert_equal 1, status
    assert_empty out
    assert_equal "error: unknown color mode \"blue\" (known modes: auto, always, never)\n", err
    assert_empty @fixture.calls
  end

  def test_unknown_theme_is_reported_as_an_error
    status, out, err = @fixture.run('get', 'projects', env: { 'SLIPWAY_THEME' => 'solarized' })

    assert_equal 1, status
    assert_empty out
    assert_equal "error: unknown theme \"solarized\" (known themes: dark, light)\n", err
    assert_empty @fixture.calls
  end
end
