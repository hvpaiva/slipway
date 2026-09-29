# frozen_string_literal: true

require 'test_helper'

class ParserTest < Minitest::Test
  def setup
    @fixture = FixtureRegistry.new
    @values = {}
  end

  def test_short_switch_with_attached_value
    rest = command_parser.permute!(%w[projects -ojson])

    assert_equal %w[projects], rest
    assert_equal 'json', @values[:output]
  end

  def test_long_switch_with_equals_or_a_separate_word
    command_parser.permute!(%w[--output=json])
    yaml = {}
    Slipway::CLI::Parser.new(output_options, yaml).permute!(%w[--output yaml])

    assert_equal 'json', @values[:output]
    assert_equal 'yaml', yaml[:output]
  end

  def test_double_dash_ends_option_parsing
    rest = command_parser.permute!(%w[projects -- -o json])

    assert_equal %w[projects -o json], rest
    assert_empty @values
  end

  def test_order_stops_at_the_first_word
    rest = globals_parser.order!(%w[-n work get -o json])

    assert_equal %w[get -o json], rest
    assert_equal 'work', @values[:group]
  end

  def test_permute_interleaves_options_and_words
    rest = command_parser.permute!(%w[projects -o json alpha --no-headers beta])

    assert_equal %w[projects alpha beta], rest
    assert_equal 'json', @values[:output]
    assert @values[:no_headers]
  end

  def test_missing_argument_raises
    error = assert_raises(OptionParser::MissingArgument) { command_parser.permute!(%w[projects -o]) }

    assert_equal 'missing argument: -o', error.message
  end

  def test_unknown_and_abbreviated_switches_raise_invalid_option
    bogus = assert_raises(OptionParser::InvalidOption) { command_parser.permute!(%w[--bogus]) }
    abbreviated = assert_raises(OptionParser::InvalidOption) { command_parser.permute!(%w[--outp json]) }

    assert_equal '--bogus', bogus.args.first
    assert_equal '--outp', abbreviated.args.first
    assert_raises(OptionParser::InvalidOption) { command_parser.permute!(%w[-x]) }
  end

  def test_repeatable_options_accumulate
    Slipway::CLI::Parser.new(@fixture.command('create').options, @values).permute!(%w[--label a=b --label c=d])

    assert_equal %w[a=b c=d], @values[:label]
  end

  def test_bare_color_means_always_and_equals_carries_a_value
    globals_parser.order!(%w[--color get])
    never = {}
    Slipway::CLI::Parser.new(Slipway::CLI::Globals::ALL, never).order!(%w[--color=never get])

    assert_equal 'always', @values[:color]
    assert_equal 'never', never[:color]
  end

  def test_defaults_fill_only_what_was_not_given
    parser = command_parser
    parser.permute!(%w[--no-headers])

    assert_equal({ no_headers: true, output: 'table', selector: nil }, parser.defaults)
  end

  def test_officious_completion_switches_are_removed
    assert_raises(OptionParser::InvalidOption) { command_parser.permute!(%w[--*-completion-bash=--o]) }
    assert_raises(OptionParser::InvalidOption) { command_parser.permute!(%w[--*-completion-zsh]) }
  end

  private

  def output_options = @fixture.command('get').options

  def command_parser = Slipway::CLI::Parser.new(output_options, @values)

  def globals_parser = Slipway::CLI::Parser.new(Slipway::CLI::Globals::ALL, @values)
end
