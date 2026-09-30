# frozen_string_literal: true

require 'test_helper'

class ExplainOutputTest < Minitest::Test
  include OutputHelper

  FIELD = Slipway::Output::Explain::Field
  LEAF = FIELD.new(name: 'path', type: 'string', required: true, description: 'Where it is.', fields: [])
  NOTE = FIELD.new(name: 'note', type: 'string', required: false, description: 'Free text.', fields: [])
  SPEC = FIELD.new(name: 'spec', type: 'Object', required: true, description: 'The spec.', fields: [LEAF, NOTE])
  ROOT = FIELD.new(name: 'Thing', type: 'Object', required: false, description: 'A thing.', fields: [SPEC])

  def test_a_resource_lists_its_fields_with_their_descriptions_one_blank_line_apart
    expected = <<~TEXT
      KIND: Thing

      DESCRIPTION:
          The spec.

      FIELDS:
        path   <string> -required-
          Where it is.

        note   <string>
          Free text.
    TEXT

    assert_equal expected, render(kind: 'Thing', field: SPEC)
  end

  def test_a_named_field_gets_the_field_line_and_a_leaf_no_fields_section
    expected = <<~TEXT
      KIND: Thing

      FIELD: path <string> -required-

      DESCRIPTION:
          Where it is.
    TEXT

    assert_equal expected, render(kind: 'Thing', field: LEAF, named: true)
  end

  def test_recursive_prints_the_whole_tree_with_the_types_in_one_column
    expected = <<~TEXT
      KIND: Thing

      DESCRIPTION:
          A thing.

      FIELDS:
        spec     <Object> -required-
          path   <string> -required-
          note   <string>
    TEXT

    assert_equal expected, render(kind: 'Thing', field: ROOT, recursive: true)
  end

  def test_descriptions_wrap_at_eighty_columns_under_their_indent
    words = Array.new(30) { 'word' }.join(' ')
    lines = render(kind: 'Thing', field: ROOT.with(description: words, fields: [NOTE.with(description: words)]))
            .lines(chomp: true)

    assert_equal ["    #{Array.new(15) { 'word' }.join(' ')}", "    #{Array.new(15) { 'word' }.join(' ')}"],
                 lines[3, 2]
    assert_operator lines.map(&:size).max, :<=, 80
    assert_equal ["    #{'word ' * 14}word", "    #{'word ' * 14}word"], lines[-2, 2]
  end

  def test_a_word_longer_than_the_line_keeps_a_line_of_its_own
    long = 'x' * 90

    assert_equal "DESCRIPTION:\n    short\n    #{long}\n    short\n",
                 render(kind: 'Thing', field: NOTE.with(description: "short #{long} short")).split("\n\n").last
  end

  def test_color_paints_the_labels_the_names_by_depth_and_the_required_mark
    context = colored_context

    rendered = Slipway::Output::Explain.new(context).render(kind: 'Thing', field: ROOT, recursive: true)

    assert_includes rendered, "\e[96mKIND\e[0m: Thing"
    assert_includes rendered, "\e[96mFIELDS\e[0m:\n"
    assert_includes rendered, "  \e[96mspec\e[0m     <Object> \e[31m-required-\e[0m\n"
    assert_includes rendered, "    \e[36mpath\e[0m   <string> \e[31m-required-\e[0m\n"
  end

  def test_print_writes_the_rendered_text
    context = plain_context

    Slipway::Output::Explain.new(context).print(kind: 'Thing', field: LEAF)

    assert_equal render(kind: 'Thing', field: LEAF), context.out.string
  end

  private

  def render(**) = Slipway::Output::Explain.new(plain_context).render(**)
end
