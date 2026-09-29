# frozen_string_literal: true

require 'test_helper'

class ContextTest < Minitest::Test
  def setup
    @out = StringIO.new
    @err = StringIO.new
  end

  def test_defaults_are_plain_streams_without_color
    context = Slipway::CLI::Context.new(out: @out, err: @err)

    refute_predicate context, :color?
    refute context.tty
    refute context.err_tty
    assert_empty context.env
  end

  def test_with_color_resolves_each_stream_on_its_own
    context = Slipway::CLI::Context.new(out: @out, err: @err, tty: true, err_tty: false).with_color('auto')

    assert_predicate context, :color?
    assert_equal "\e[93mx\e[0m", context.paint(:string, 'x')
    assert_equal 'x', context.paint_err(:string, 'x')
  end

  def test_with_color_applies_the_given_theme_to_both_streams
    light = Slipway::CLI::Theme.fetch('light')
    context = Slipway::CLI::Context.new(out: @out, err: @err, tty: true, err_tty: true)
    context = context.with_color('always', theme: light)

    assert_equal 'light', context.style.theme.name
    assert_equal 'light', context.err_style.theme.name
    assert_equal "\e[34mflag\e[0m", context.paint_err(:help_flag, 'flag')
  end

  def test_with_color_reads_the_environment_of_the_context
    context = Slipway::CLI::Context.new(out: @out, err: @err, tty: true, err_tty: true, env: { 'NO_COLOR' => '1' })
    context = context.with_color('auto')

    refute_predicate context, :color?
    refute_predicate context.err_style, :enabled?
  end

  def test_writes_go_to_the_right_stream
    context = Slipway::CLI::Context.new(out: @out, err: @err)
    context.puts('one', 'two')
    context.print('three')
    context.warn('oops')

    assert_equal "one\ntwo\nthree", @out.string
    assert_equal "oops\n", @err.string
  end

  def test_system_context_wraps_the_process_streams
    context = Slipway::CLI::Context.system

    assert_same $stdout, context.out
    assert_same $stderr, context.err
    assert_same ENV, context.env
    assert_equal $stdout.tty?, context.tty
    assert_equal $stderr.tty?, context.err_tty
  end
end
