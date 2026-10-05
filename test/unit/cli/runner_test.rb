# frozen_string_literal: true

require 'test_helper'

class RunnerTest < Minitest::Test
  def setup
    @fixture = FixtureRegistry.new
  end

  def test_a_missing_command_prints_the_summary_on_stderr_as_a_usage_error
    assert_equal [2, '', renderer.root(long: false)], @fixture.run
    assert_equal [2, '', renderer.command(*resolve('config'), long: false)], @fixture.run('config')
    assert_includes @fixture.run(err_tty: true)[2], "\e[1mUsage:\e[0m slipway [OPTIONS] <COMMAND>\n"
    assert_equal [0, renderer.root, ''], @fixture.run('--help')
    assert_empty @fixture.calls
  end

  def test_short_help_prints_the_summary_and_long_help_the_page
    summary = [0, renderer.command(*resolve('get'), long: false), '']

    assert_equal [0, renderer.command(*resolve('get')), ''], @fixture.run('get', '--help')
    assert_equal summary, @fixture.run('-h', 'get')
    assert_equal summary, @fixture.run('get', '-hV')
    assert_equal summary, @fixture.run('get', '-h', '--', '--help')
    assert_empty @fixture.calls
  end

  def test_help_wraps_at_the_width_columns_gives
    assert_equal [0, renderer(width: 60).command(*resolve('get'), long: false), ''],
                 @fixture.run('get', '-h', env: { 'COLUMNS' => '60' })
  end

  def test_version_flags_print_the_version_line
    status, out, err = @fixture.run('--version')

    assert_equal 0, status
    assert_equal "slipway 0.1.0 (ruby #{RUBY_VERSION}) [#{Gem::Platform.local}]\n", out
    assert_empty err
    assert_equal out, @fixture.run('-V')[1]
  end

  def test_success_dispatches_args_and_defaulted_opts_to_the_handler
    status, out, err = @fixture.run('get', 'projects', 'alpha', '-o', 'json')
    call = @fixture.calls.fetch(0)

    assert_equal [0, '', ''], [status, out, err]
    assert_equal ['get', %w[projects alpha]], [call.name, call.args]
    assert_equal({ output: 'json', no_headers: nil, selector: nil }, call.opts.slice(:output, :no_headers, :selector))
    assert_nil call.opts.fetch(:group)
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
    assert_equal 'error: invalid argument "xml" for --output: must be one of table, wide, json, ' \
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

  def test_error_lines_make_control_characters_visible
    @fixture.failure = Slipway::Error.new(problems: ["/srv/x: git exited with status 128: fatal: \e[2Jgone\u202E",
                                                     "\e]52;c;cHduZWQ=\a\nforged"])
    _, _, err = @fixture.run('get', 'projects', err_tty: true)

    assert_equal "\e[31merror:\e[0m /srv/x: git exited with status 128: fatal: ^[[2Jgone\uFFFD\n" \
                 "\e[31merror:\e[0m ^[]52;c;cHduZWQ=^G^Jforged\n", err
  end

  def test_error_lines_accept_binary_text_from_the_c_locale
    @fixture.failure = Slipway::Error.new("/nonexistent/proje\xC3\xA7\xC3\xA3o\e.yaml: no such file".b)
    status, _, err = @fixture.run('get', 'projects')

    assert_equal 1, status
    assert_equal "error: /nonexistent/proje\u00E7\u00E3o^[.yaml: no such file\n", err
  end

  def test_a_hint_is_made_visible_too
    @fixture.failure = Slipway::CLI::UsageError.new('nope', hint: "Run \e[8mhidden\e[0m.")
    _, _, err = @fixture.run('config', 'view')

    assert_equal "error: nope\nRun ^[[8mhidden^[[0m.\n", err
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
    assert_equal "error: SLIPWAY_COLOR: must be one of auto, always, never\n", err
    assert_empty @fixture.calls
  end

  def test_unknown_theme_is_reported_as_an_error
    status, out, err = @fixture.run('get', 'projects', env: { 'SLIPWAY_THEME' => 'solarized' })

    assert_equal 1, status
    assert_empty out
    assert_equal "error: SLIPWAY_THEME: must be one of dark, light\n", err
    assert_empty @fixture.calls
  end

  private

  def renderer(width: nil) = Slipway::CLI::HelpRenderer.new(@fixture.registry, Slipway::CLI::Style.disabled, width:)

  def resolve(*words) = @fixture.registry.resolve(words)
end
