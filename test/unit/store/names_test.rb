# frozen_string_literal: true

require 'test_helper'
require 'slipway/names'

class NamesTest < Minitest::Test
  VALID = ['a', '7', 'hldr', 'my-project', '3d-viewer', 'a-b-c', 'abc123', 'a' * 63].freeze
  INVALID = ['', 'Hldr', 'my_project', '-abc', 'abc-', 'a.b', 'a b', 'a/b', '..', 'a' * 64].freeze
  RULE = 'lowercase letters, digits and dashes, starting and ending with a letter or digit, at most 63 characters'

  def test_valid_accepts_rfc_1123_labels
    VALID.each { assert Slipway::Names.valid?(it), "#{it.inspect} should be valid" }
  end

  def test_valid_rejects_anything_else
    INVALID.each { refute Slipway::Names.valid?(it), "#{it.inspect} should be invalid" }
  end

  def test_valid_rejects_values_that_are_not_strings
    refute Slipway::Names.valid?(nil)
    refute Slipway::Names.valid?(:hldr)
    refute Slipway::Names.valid?(42)
  end

  def test_validate_returns_the_name
    assert_equal 'hldr', Slipway::Names.validate!('hldr')
  end

  def test_validate_names_the_field_in_its_message
    error = assert_raises(Slipway::Error) { Slipway::Names.validate!('Bad Name', what: 'project name') }

    assert_equal "\"Bad Name\" is not a valid project name: #{RULE}", error.message
    assert_equal 1, error.exit_status
    assert_nil error.hint
  end

  def test_validate_defaults_the_field_to_name
    error = assert_raises(Slipway::Error) { Slipway::Names.validate!('') }

    assert_equal "\"\" is not a valid name: #{RULE}", error.message
  end
end
