# frozen_string_literal: true

require 'test_helper'
require 'slipway/labels'

class LabelsTest < Minitest::Test
  VALID_KEYS = ['a', 'lang', 'A_b.c-D', 'app.kubernetes.io/name', 'example.com/my-app', 'a' * 63,
                "#{'a' * 253}/x"].freeze
  INVALID_KEYS = ['', '-a', 'a-', '_a', 'a.', 'a b', 'a/b/c', '/a', 'a/', 'Example.com/a', 'a_b/x', 'a' * 64,
                  "#{'a' * 254}/x", "example.com/#{'a' * 64}"].freeze
  VALID_VALUES = ['', 'rust', 'a-b_c.d', 'A1', 'a' * 63].freeze
  INVALID_VALUES = ['-a', 'a-', '.a', 'a b', 'a/b', 'a' * 64].freeze
  KEY_RULE = 'letters, digits, dashes, underscores and dots, starting and ending with a letter or digit, ' \
             'at most 63 characters, with an optional DNS subdomain prefix and a slash'
  VALUE_RULE = 'empty, or letters, digits, dashes, underscores and dots, starting and ending with a letter ' \
               'or digit, at most 63 characters'

  def test_valid_key_accepts_kubernetes_qualified_names
    VALID_KEYS.each { assert Slipway::Labels.valid_key?(it), "#{it.inspect} should be a valid key" }
  end

  def test_valid_key_rejects_malformed_names_and_prefixes
    INVALID_KEYS.each { refute Slipway::Labels.valid_key?(it), "#{it.inspect} should be an invalid key" }

    refute Slipway::Labels.valid_key?(nil)
    refute Slipway::Labels.valid_key?(:lang)
  end

  def test_valid_value_accepts_empty_and_qualified_values
    VALID_VALUES.each { assert Slipway::Labels.valid_value?(it), "#{it.inspect} should be a valid value" }
  end

  def test_valid_value_rejects_malformed_values
    INVALID_VALUES.each { refute Slipway::Labels.valid_value?(it), "#{it.inspect} should be an invalid value" }

    refute Slipway::Labels.valid_value?(nil)
    refute Slipway::Labels.valid_value?(1)
  end

  def test_validate_returns_the_labels
    labels = { 'lang' => 'rust', 'example.com/tier' => '' }

    assert_same labels, Slipway::Labels.validate!(labels)
  end

  def test_validate_reports_the_first_bad_key
    error = assert_raises(Slipway::Error) { Slipway::Labels.validate!({ 'lang' => 'rust', '-x' => 'y' }) }

    assert_equal "\"-x\" is not a valid label key: #{KEY_RULE}", error.message
    assert_equal 1, error.exit_status
  end

  def test_validate_reports_a_bad_value
    error = assert_raises(Slipway::Error) { Slipway::Labels.validate!({ 'lang' => 'a b' }) }

    assert_equal "\"a b\" is not a valid label value: #{VALUE_RULE}", error.message
  end

  def test_parse_pairs_builds_a_hash_in_word_order
    assert_equal({ 'lang' => 'rust', 'team' => '' }, Slipway::Labels.parse_pairs(%w[lang=rust team=]))
    assert_empty Slipway::Labels.parse_pairs([])
  end

  def test_parse_pairs_rejects_a_word_without_an_equals_sign
    error = assert_raises(Slipway::CLI::UsageError) { Slipway::Labels.parse_pairs(%w[lang=rust foo]) }

    assert_equal 'invalid label "foo": expected KEY=VALUE', error.message
    assert_equal 2, error.exit_status
  end

  def test_parse_pairs_rejects_a_repeated_key
    error = assert_raises(Slipway::CLI::UsageError) { Slipway::Labels.parse_pairs(%w[lang=rust lang=go]) }

    assert_equal 'label "lang" is given more than once', error.message
  end

  def test_parse_pairs_turns_key_and_value_rules_into_usage_errors
    key_error = assert_raises(Slipway::CLI::UsageError) { Slipway::Labels.parse_pairs(['Bad Key=1']) }
    value_error = assert_raises(Slipway::CLI::UsageError) { Slipway::Labels.parse_pairs(['lang=a=b']) }

    assert_equal "\"Bad Key\" is not a valid label key: #{KEY_RULE}", key_error.message
    assert_equal "\"a=b\" is not a valid label value: #{VALUE_RULE}", value_error.message
  end

  def test_parse_changes_separates_sets_from_removals
    sets, removals = Slipway::Labels.parse_changes(%w[a=1 b- c= d-])

    assert_equal({ 'a' => '1', 'c' => '' }, sets)
    assert_equal %w[b d], removals
  end

  def test_parse_changes_of_nothing_is_empty
    assert_equal [{}, []], Slipway::Labels.parse_changes([])
  end

  def test_parse_changes_rejects_a_word_that_is_neither
    error = assert_raises(Slipway::CLI::UsageError) { Slipway::Labels.parse_changes(%w[x]) }

    assert_equal 'invalid label "x": expected KEY=VALUE or KEY-', error.message
  end

  def test_parse_changes_rejects_setting_and_removing_one_key
    error = assert_raises(Slipway::CLI::UsageError) { Slipway::Labels.parse_changes(%w[a=1 a-]) }

    assert_equal 'label "a" cannot be both set and removed', error.message
  end

  def test_parse_changes_rejects_repeated_words
    set_error = assert_raises(Slipway::CLI::UsageError) { Slipway::Labels.parse_changes(%w[a=1 a=2]) }
    removal_error = assert_raises(Slipway::CLI::UsageError) { Slipway::Labels.parse_changes(%w[a- a-]) }

    assert_equal 'label "a" is given more than once', set_error.message
    assert_equal 'label "a" is given more than once', removal_error.message
  end

  def test_parse_changes_validates_the_removed_key
    error = assert_raises(Slipway::CLI::UsageError) { Slipway::Labels.parse_changes(%w[-]) }

    assert_equal "\"\" is not a valid label key: #{KEY_RULE}", error.message
  end

  def test_parse_changes_reads_a_trailing_dash_after_equals_as_part_of_the_value
    error = assert_raises(Slipway::CLI::UsageError) { Slipway::Labels.parse_changes(%w[a=b-]) }

    assert_equal "\"b-\" is not a valid label value: #{VALUE_RULE}", error.message
  end

  def test_format_sorts_pairs_by_key
    assert_equal 'lang=rust,tier=', Slipway::Labels.format({ 'tier' => '', 'lang' => 'rust' })
  end

  def test_format_of_no_labels_is_nil
    assert_nil Slipway::Labels.format({})
  end
end
