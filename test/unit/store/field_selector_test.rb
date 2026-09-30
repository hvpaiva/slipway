# frozen_string_literal: true

require 'test_helper'
require 'slipway/field_selector'

class FieldSelectorTest < Minitest::Test
  FIELDS = { 'metadata.name' => '', 'spec.path' => '', 'spec.note' => 'unset', 'status.state' => '',
             'status.branch' => '', 'status.upstream' => '' }.freeze
  OBJECT = { 'metadata' => { 'name' => 'hldr' }, 'spec' => { 'path' => '~/dev/a,b=c\\d' },
             'status' => { 'state' => 'Clean', 'branch' => 'main' } }.freeze

  MATCHING = ['metadata.name=hldr', 'metadata.name==hldr', 'metadata.name!=notes',
              'status.state=Clean,status.branch=main', 'status.branch!=', 'status.upstream=',
              'status.upstream!=origin/main', 'spec.note=unset', 'spec.path=~/dev/a\\,b\\=c\\\\d',
              'status.state=Clean,', ',status.state=Clean,,', '', ' status.state=Clean '].freeze
  NOT_MATCHING = ['metadata.name=notes', 'metadata.name!=hldr', 'status.state=clean',
                  'status.state=Clean,status.branch=dev', 'status.upstream!=', 'spec.note=', 'spec.note!=unset',
                  'status.branch='].freeze

  INVALID = {
    'status.state' => "can't understand \"status.state\"",
    'status.state=Clean,dirty' => "can't understand \"dirty\"",
    'status.phase=Running' => 'field label not supported: "status.phase"',
    '=Clean' => 'field label not supported: ""',
    'status.state=Clean, status.branch=main' => 'field label not supported: " status.branch"',
    'status.state=Cl=ean' => 'unescaped character in value: =',
    'metadata.name!==hldr' => 'unescaped character in value: =',
    'metadata.name=a\\x' => 'invalid escape sequence: \\x',
    'metadata.name=a\\' => 'invalid escape sequence: \\'
  }.freeze

  def test_a_term_holds_when_its_field_compares_as_it_says
    MATCHING.each { assert selects?(it, OBJECT), "#{it.inspect} should match" }
  end

  def test_a_selector_fails_when_any_term_fails
    NOT_MATCHING.each { refute selects?(it, OBJECT), "#{it.inspect} should not match" }
  end

  def test_the_leftmost_operator_splits_a_term
    assert selects?('metadata.name=!x', { 'metadata' => { 'name' => '!x' } })
    assert selects?('metadata.name!=x', { 'metadata' => { 'name' => 'y' } })
    refute selects?('metadata.name==x', { 'metadata' => { 'name' => '=x' } })
  end

  def test_malformed_expressions_and_unsupported_fields_are_usage_errors_with_a_reason
    INVALID.each do |expression, reason|
      error = assert_raises(Slipway::CLI::UsageError, expression.inspect) { parse(expression) }

      assert_equal "invalid field selector #{expression.inspect}: #{reason}", error.message
      assert_equal 2, error.exit_status
    end
  end

  # Under the C locale ARGV is BINARY while git and the manifest hand over UTF-8.
  def test_a_binary_expression_compares_as_utf8
    object = { 'status' => { 'branch' => 'café' } }

    assert selects?('status.branch=café'.b, object)
    refute selects?('status.branch!=café'.b, object)
    error = assert_raises(Slipway::CLI::UsageError) { parse("status.branch=\xFF".b) }
    assert_equal 'invalid field selector "status.branch=\\xFF": invalid UTF-8', error.message
  end

  def test_a_blank_expression_selects_everything
    [nil, '', " \t", ',,'].each do |expression|
      assert_predicate parse(expression), :empty?, expression.inspect
      assert selects?(expression, {})
    end
  end

  def test_filter_keeps_the_items_whose_object_matches
    items = %w[hldr notes]
    object = ->(name) { { 'metadata' => { 'name' => name } } }

    assert_equal %w[notes], parse('metadata.name!=hldr').filter(items) { object.call(it) }
    assert_same items, parse('').filter(items) { flunk 'an empty selector reads no object' }
  end

  private

  def parse(expression) = Slipway::FieldSelector.parse(expression, fields: FIELDS)

  def selects?(expression, object) = parse(expression).match?(object)
end
