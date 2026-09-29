# frozen_string_literal: true

require 'test_helper'
require 'slipway/selector'

class SelectorTest < Minitest::Test
  NORMALIZED = {
    'a=b' => 'a=b',
    'a==b' => 'a=b',
    'a!=b' => 'a!=b',
    'a' => 'a',
    '!a' => '!a',
    'a in (b,c)' => 'a in (b,c)',
    'a in (c,b,c)' => 'a in (b,c)',
    'a notin (b)' => 'a notin (b)',
    'a in ()' => 'a in ()',
    'a in (,b)' => 'a in (,b)',
    'a in (b,)' => 'a in (,b)',
    'a=' => 'a=',
    'a=,b' => 'a=,b',
    ' b = 1 , a ' => 'a,b=1',
    "x\tin\t( a , b )" => 'x in (a,b)',
    'a==b,a!=c' => 'a!=c,a=b',
    'team,!legacy,lang in (rust,go),example.com/tier!=web' => 'example.com/tier!=web,lang in (go,rust),!legacy,team',
    'a=in,b=notin' => 'a=in,b=notin',
    'a in (in,notin)' => 'a in (in,notin)'
  }.freeze

  INVALID = {
    'a,' => "expected a requirement after ','",
    ',a' => 'expected a key, found ","',
    'a,,b' => 'expected a key, found ","',
    '!' => "expected a key after '!'",
    '!!a' => "expected a key after '!'",
    '!a=b' => "expected ',' or the end of the selector",
    'a in' => "expected '(' after \"in\"",
    'a in (' => "expected ',' or ')' in the value set",
    'a in (b' => "expected ',' or ')' in the value set",
    'a in b' => "expected '(' after \"in\"",
    'a in ((b))' => "expected ',' or ')' in the value set",
    'a b' => 'unexpected "b" after "a"',
    'a b=c' => 'unexpected "b" after "a"',
    'a=b c' => "expected ',' or the end of the selector",
    '=a' => 'expected a key, found "="',
    'a=(' => 'expected a value, found "("',
    'in=a' => 'expected a key, found "in"',
    '!notin' => "expected a key after '!'",
    'a/b/c=1' => 'invalid label key "a/b/c"',
    '-a' => 'invalid label key "-a"',
    'a=-b' => 'invalid label value "-b"',
    'a in (b,c d)' => "expected ',' or ')' in the value set",
    'a notin (x/y)' => 'invalid label value "x/y"'
  }.freeze

  LABELS = { 'lang' => 'rust', 'tier' => 'cli', 'empty' => '' }.freeze

  MATCHING = ['lang=rust', 'lang==rust', 'lang!=go', 'missing!=x', 'tier', '!missing', 'lang in (go,rust)',
              'lang notin (go)', 'missing notin (a)', 'lang=rust,tier=cli', 'empty=', 'empty in ()', ''].freeze
  NOT_MATCHING = ['lang!=rust', 'lang=go', '!tier', 'missing', 'missing in (a)', 'lang in (go)', 'lang notin (rust)',
                  'lang=rust,tier=web', 'lang=', 'tier in ()'].freeze

  def test_parse_normalizes_every_form_of_the_grammar
    NORMALIZED.each do |expression, expected|
      assert_equal expected, Slipway::Selector.parse(expression).to_s, expression.inspect
    end
  end

  def test_to_s_round_trips
    NORMALIZED.each_value do |normalized|
      assert_equal normalized, Slipway::Selector.parse(normalized).to_s
    end
  end

  def test_malformed_expressions_are_usage_errors_with_a_reason
    INVALID.each do |expression, reason|
      error = assert_raises(Slipway::CLI::UsageError, expression.inspect) { Slipway::Selector.parse(expression) }

      assert_equal "invalid selector #{expression.inspect}: #{reason}", error.message
    end
  end

  def test_usage_errors_exit_with_status_2_and_leave_the_hint_to_the_runner
    error = assert_raises(Slipway::CLI::UsageError) { Slipway::Selector.parse('a,') }

    assert_equal 2, error.exit_status
    assert_nil error.hint
  end

  def test_match_holds_when_every_requirement_holds
    MATCHING.each { assert selects?(it, LABELS), "#{it.inspect} should match" }
  end

  def test_match_fails_when_any_requirement_fails
    NOT_MATCHING.each { refute selects?(it, LABELS), "#{it.inspect} should not match" }
  end

  def test_a_blank_expression_selects_everything
    [nil, '', "  \t "].each do |expression|
      selector = Slipway::Selector.parse(expression)

      assert_predicate selector, :empty?
      assert_equal '', selector.to_s
      assert selects?(expression, {})
    end
  end

  def test_requirements_are_exposed_as_frozen_data
    selector = Slipway::Selector.parse('!legacy,lang in (rust,go)')
    summary = selector.requirements.map { [it.key, it.operator.to_s] }

    assert_predicate selector.requirements, :frozen?
    assert_equal [%w[lang in], %w[legacy does_not_exist]], summary
    assert_equal %w[go rust], selector.requirements.first.values
    refute_predicate selector, :empty?
  end

  private

  def selects?(expression, labels) = Slipway::Selector.parse(expression).match?(labels)
end
