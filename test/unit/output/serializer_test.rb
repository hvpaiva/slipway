# frozen_string_literal: true

require 'test_helper'

class SerializerTest < Minitest::Test
  PROJECT = { 'kind' => 'Project', 'metadata' => { 'name' => 'hldr' }, 'status' => { 'ahead' => 0 } }.freeze
  GROUP = { 'kind' => 'Group', 'metadata' => { 'name' => 'personal' } }.freeze

  def test_json_of_a_single_object_ends_with_a_newline
    expected = <<~JSON
      {
        "kind": "Project",
        "metadata": {
          "name": "hldr"
        },
        "status": {
          "ahead": 0
        }
      }
    JSON

    assert_equal expected, render('json', [PROJECT, GROUP], single: true)
  end

  def test_json_of_many_objects_is_a_list
    expected = <<~JSON
      {
        "kind": "List",
        "items": [
          {
            "kind": "Group",
            "metadata": {
              "name": "personal"
            }
          }
        ]
      }
    JSON

    assert_equal expected, render('json', [GROUP], single: false)
  end

  def test_yaml_of_a_single_object_has_no_document_marker
    expected = <<~YAML
      kind: Project
      metadata:
        name: hldr
      status:
        ahead: 0
    YAML

    assert_equal expected, render('yaml', [PROJECT], single: true)
  end

  def test_yaml_of_many_objects_is_a_list
    expected = <<~YAML
      kind: List
      items:
      - kind: Project
        metadata:
          name: hldr
        status:
          ahead: 0
      - kind: Group
        metadata:
          name: personal
    YAML

    assert_equal expected, render('yaml', [PROJECT, GROUP], single: false)
  end

  def test_an_empty_list_keeps_the_list_shape
    assert_equal "{\n  \"kind\": \"List\",\n  \"items\": []\n}\n", render('json', [], single: false)
    assert_equal "kind: List\nitems: []\n", render('yaml', [], single: false)
  end

  def test_yaml_never_folds_long_strings
    text = 'word ' * 60
    item = { 'spec' => { 'description' => text.strip } }

    assert_equal "spec:\n  description: #{text.strip}\n", render('yaml', [item], single: true)
  end

  def test_yaml_refuses_a_time_because_callers_pass_strings
    item = { 'metadata' => { 'creationTimestamp' => Time.utc(2026, 9, 29) } }

    assert_raises(Psych::DisallowedClass) { render('yaml', [item], single: true) }
  end

  def test_only_json_and_yaml_are_structured_formats
    assert_equal %w[table wide json yaml name], Slipway::Output::Serializer::FORMATS
    error = assert_raises(ArgumentError) { render('table', [PROJECT], single: true) }
    assert_equal 'unknown structured format "table" (known formats: json, yaml)', error.message
  end

  private

  def render(format, items, single:) = Slipway::Output::Serializer.render(format, items, single:)
end
