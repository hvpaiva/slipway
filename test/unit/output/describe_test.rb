# frozen_string_literal: true

require 'test_helper'

class DescribeTest < Minitest::Test
  include OutputHelper

  def test_values_align_two_spaces_past_the_longest_key
    entries = [%w[Name hldr], %w[Group personal], ['Path', '~/dev/personal/hldr']]
    expected = <<~TEXT
      Name:   hldr
      Group:  personal
      Path:   ~/dev/personal/hldr
    TEXT

    assert_equal expected, render(entries)
  end

  def test_the_key_column_grows_with_the_longest_key_of_the_block
    assert_equal "Name:         hldr\nDescription:  Site\n", render([%w[Name hldr], %w[Description Site]])
  end

  def test_empty_values_read_as_none
    entries = [['Labels', {}], ['Remotes', []], ['Upstream', nil]]

    assert_equal "Labels:    <none>\nRemotes:   <none>\nUpstream:  <none>\n", render(entries)
  end

  def test_lists_continue_under_the_first_item
    assert_equal "Remotes:  origin\n          upstream\n", render([['Remotes', %w[origin upstream]]])
  end

  def test_labels_are_sorted_and_written_as_pairs
    entries = [['Labels', { 'lang' => 'rust', 'app' => 'web' }], %w[Name hldr]]

    assert_equal "Labels:  app=web\n         lang=rust\nName:    hldr\n", render(entries)
  end

  def test_nested_sections_indent_by_two_and_align_on_their_own
    entries = [%w[Name hldr], ['Git', [%w[Branch main], ['Ahead', 0]]], %w[Status Clean]]
    expected = <<~TEXT
      Name:    hldr
      Git:
        Branch:  main
        Ahead:   0
      Status:  Clean
    TEXT

    assert_equal expected, render(entries)
  end

  def test_lists_inside_a_section_align_with_the_indented_key_column
    assert_equal "Git:\n  Remotes:  a\n            b\n", render([['Git', [['Remotes', %w[a b]]]]])
  end

  def test_times_are_written_as_rfc_3339_utc
    created = Time.new(2026, 9, 29, 3, 12, 33, '+03:00')

    assert_equal "Created:  2026-09-29T00:12:33Z\n", render([['Created', created]])
  end

  def test_no_entries_render_nothing
    assert_equal '', render([])
  end

  def test_typed_values_take_their_role_and_strings_stay_plain
    painted = Slipway::Output::Painted.new(role: :status_warning, text: 'Dirty')
    entries = [['Ahead', 2], ['Clean', true], ['Detached', false], ['Upstream', nil], ['State', painted], %w[Name hldr]]
    expected = "\e[96mAhead\e[0m:     \e[35m2\e[0m\n" \
               "\e[96mClean\e[0m:     \e[32mtrue\e[0m\n" \
               "\e[96mDetached\e[0m:  \e[31mfalse\e[0m\n" \
               "\e[96mUpstream\e[0m:  \e[90;3m<none>\e[0m\n" \
               "\e[96mState\e[0m:     \e[33mDirty\e[0m\n" \
               "\e[96mName\e[0m:      hldr\n"

    assert_equal expected, render(entries, colored_context)
  end

  def test_keys_cycle_the_describe_colors_by_depth
    entries = [['Git', [['Commit', [%w[Author me]]]]]]
    dark = "\e[96mGit\e[0m:\n  \e[36mCommit\e[0m:\n    \e[96mAuthor\e[0m:  me\n"
    light = "\e[94mGit\e[0m:\n  \e[34mCommit\e[0m:\n    \e[94mAuthor\e[0m:  me\n"

    assert_equal dark, render(entries, colored_context)
    assert_equal light, render(entries, colored_context(theme: 'light'))
  end

  def test_print_writes_the_block_to_stdout
    context = plain_context
    Slipway::Output::Describe.new(context).print([%w[Name hldr]])

    assert_equal "Name:  hldr\n", context.out.string
    assert_empty context.err.string
  end

  private

  def render(entries, context = plain_context) = Slipway::Output::Describe.new(context).render(entries)
end
