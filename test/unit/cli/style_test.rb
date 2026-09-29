# frozen_string_literal: true

require 'test_helper'

class StyleTest < Minitest::Test
  def test_explicit_modes_ignore_the_stream_and_the_environment
    assert enabled?('always', tty: false, env: { 'NO_COLOR' => '1', 'TERM' => 'dumb' })
    refute enabled?('never', tty: true, env: { 'FORCE_COLOR' => '1' })
  end

  def test_auto_follows_the_stream
    assert enabled?('auto', tty: true, env: {})
    refute enabled?('auto', tty: false, env: {})
  end

  def test_auto_honours_no_color_only_when_it_is_non_empty
    refute enabled?('auto', tty: true, env: { 'NO_COLOR' => '1' })
    assert enabled?('auto', tty: true, env: { 'NO_COLOR' => '' })
  end

  def test_auto_forces_color_on_a_pipe_with_force_color_or_clicolor_force
    assert enabled?('auto', tty: false, env: { 'FORCE_COLOR' => '1' })
    assert enabled?('auto', tty: false, env: { 'CLICOLOR_FORCE' => '1' })
    refute enabled?('auto', tty: false, env: { 'FORCE_COLOR' => '' })
  end

  def test_auto_precedence_is_no_color_then_force_then_dumb_terminal
    refute enabled?('auto', tty: true, env: { 'NO_COLOR' => '1', 'FORCE_COLOR' => '1' })
    assert enabled?('auto', tty: false, env: { 'FORCE_COLOR' => '1', 'TERM' => 'dumb' })
    refute enabled?('auto', tty: true, env: { 'TERM' => 'dumb' })
  end

  def test_paint_wraps_text_in_the_role_sgr_when_enabled
    style = Slipway::CLI::Style.for('always', tty: false, env: {})

    assert_equal "\e[93mhldr\e[0m", style.paint(:string, 'hldr')
    assert_equal "\e[35m3\e[0m", style.paint(:number, 3)
    assert_equal "\e[31merror:\e[0m", style.paint(:error, 'error:')
  end

  def test_paint_returns_plain_text_when_disabled
    style = Slipway::CLI::Style.disabled

    refute_predicate style, :enabled?
    assert_equal 'hldr', style.paint(:string, 'hldr')
    assert_equal '3', style.paint(:number, 3)
    assert_equal 'x', style.paint_cycle(:table_columns, 1, 'x')
  end

  def test_paint_cycle_wraps_around_list_roles
    dark = Slipway::CLI::Style.for('always', tty: false, env: {})
    light = Slipway::CLI::Style.for('always', tty: false, env: {}, theme: Slipway::CLI::Theme.fetch('light'))

    assert_equal "\e[37mNAME\e[0m", dark.paint_cycle(:table_columns, 0, 'NAME')
    assert_equal "\e[36mBRANCH\e[0m", dark.paint_cycle(:table_columns, 1, 'BRANCH')
    assert_equal "\e[37mSTATUS\e[0m", dark.paint_cycle(:table_columns, 2, 'STATUS')
    assert_equal "\e[94mName\e[0m", light.paint_cycle(:describe_keys, 0, 'Name')
    assert_equal "\e[34mPath\e[0m", light.paint_cycle(:describe_keys, 1, 'Path')
  end

  def test_unknown_roles_are_programming_errors
    style = Slipway::CLI::Style.for('always', tty: false, env: {})

    assert_raises(KeyError) { style.paint(:nope, 'x') }
    assert_raises(ArgumentError) { style.paint(:table_columns, 'x') }
  end

  def test_plain_with_layout_keeps_line_feeds_and_tabs_and_nothing_else
    message = "unknown command\n\nDid you mean this?\n\tget\e[2J\r\u202E\n"

    assert_equal "unknown command\n\nDid you mean this?\n\tget^[[2J^M\uFFFD\n",
                 Slipway::CLI::Style.plain(message, layout: true)
    assert_equal 'a^Jb^Ic', Slipway::CLI::Style.plain("a\nb\tc")
  end

  def test_plain_reads_binary_text_as_utf8
    assert_equal "caf\u00E9 ^[", Slipway::CLI::Style.plain("caf\xC3\xA9 \e".b)
    assert_equal "x\uFFFDy", Slipway::CLI::Style.plain("x\xFFy".b)
    assert_equal Encoding::UTF_8, Slipway::CLI::Style.plain('plain'.b).encoding
  end

  private

  def enabled?(mode, tty:, env:) = Slipway::CLI::Style.for(mode, tty:, env:).enabled?
end

class ThemeTest < Minitest::Test
  DARK = {
    table_header: '1', table_columns: %w[37 36], describe_keys: %w[96 36],
    string: '93', number: '35', boolean_true: '32', boolean_false: '31', none: '90;3',
    status_success: '32', status_warning: '33', status_danger: '31', muted: '90;3',
    help_header: '1', help_flag: '36', help_command: '32', help_comment: '90;3',
    apply_created: '32', apply_configured: '33', apply_unchanged: '35',
    create_created: '32', delete_deleted: '31',
    label_labeled: '32', label_unlabeled: '33', label_not_labeled: '90;3',
    dry_run: '36', error: '31', warning: '33'
  }.freeze

  LIGHT = DARK.merge(table_columns: %w[30 34], describe_keys: %w[94 34], string: '33', help_flag: '34',
                     dry_run: '34').freeze

  def test_dark_preset_follows_kubecolor
    assert_equal DARK, Slipway::CLI::Theme::DARK
  end

  def test_light_preset_swaps_white_for_black_and_cyan_for_blue
    assert_equal LIGHT, Slipway::CLI::Theme::LIGHT
  end

  def test_fetch_by_name_and_default
    assert_equal 'light', Slipway::CLI::Theme.fetch('light').name
    assert_equal 'dark', Slipway::CLI::Theme.default.name
    assert_equal %w[dark light], Slipway::CLI::Theme::NAMES
  end

  def test_fetch_of_an_unknown_name_is_a_programming_error
    assert_raises(KeyError) { Slipway::CLI::Theme.fetch('solarized') }
  end

  def test_presets_share_the_same_roles
    assert_equal Slipway::CLI::Theme::DARK.keys, Slipway::CLI::Theme::LIGHT.keys
  end

  def test_sgr_at_cycles_through_a_list_role
    theme = Slipway::CLI::Theme.default

    assert_equal '96', theme.sgr_at(:describe_keys, 0)
    assert_equal '36', theme.sgr_at(:describe_keys, 1)
    assert_equal '96', theme.sgr_at(:describe_keys, 2)
    assert_equal '1', theme.sgr_at(:table_header, 7)
  end
end
