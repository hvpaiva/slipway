# frozen_string_literal: true

require 'test_helper'

class TableTest < Minitest::Test
  include OutputHelper

  HEADERS = %w[NAME BRANCH STATUS AGE].freeze

  def test_columns_are_three_spaces_apart_and_sized_by_the_widest_plain_cell
    rows = [%w[hldr main Clean 3d], ['slipway', nil, 'Missing', '45m']]
    expected = <<~TABLE
      NAME      BRANCH   STATUS    AGE
      hldr      main     Clean     3d
      slipway   <none>   Missing   45m
    TABLE

    assert_equal expected, table(plain_context).render(rows)
  end

  def test_headers_are_uppercased_and_other_values_are_stringified
    rows = [['personal', 3, '2d']]
    table = Slipway::Output::Table.new(plain_context, headers: %w[name Projects age])

    assert_equal "NAME       PROJECTS   AGE\npersonal   3          2d\n", table.render(rows)
  end

  def test_empty_strings_and_nils_read_as_none
    assert_equal "NAME   BRANCH   STATUS   AGE\na      <none>   <none>   b\n",
                 table(plain_context).render([['a', '', nil, 'b']])
  end

  def test_trailing_spaces_are_trimmed_on_every_line
    table = Slipway::Output::Table.new(plain_context, headers: %w[NAME STATUS])

    assert_equal "NAME   STATUS\nhldr   ok\n", table.render([%w[hldr ok]])
  end

  def test_without_headers_widths_come_from_the_data_alone
    table = Slipway::Output::Table.new(plain_context, headers: %w[NAME STATUS], show_headers: false)

    assert_equal "a    x\nbb   yy\n", table.render([%w[a x], %w[bb yy]])
  end

  def test_no_rows_prints_only_the_header_line_or_nothing
    assert_equal "NAME   BRANCH   STATUS   AGE\n", table(plain_context).render([])
    assert_equal '', table(plain_context, show_headers: false).render([])
  end

  def test_color_cycles_the_column_roles_and_leaves_padding_unpainted
    table = Slipway::Output::Table.new(colored_context, headers: %w[NAME STATUS AGE])
    expected = "\e[1mNAME   STATUS   AGE\e[0m\n" \
               "\e[37mhldr\e[0m   \e[36mClean\e[0m    \e[37m3d\e[0m\n"

    assert_equal expected, table.render([%w[hldr Clean 3d]])
  end

  def test_color_offset_keeps_the_column_colors_when_a_leading_column_is_added
    plain = Slipway::Output::Table.new(colored_context, headers: %w[NAME STATUS])
    grouped = Slipway::Output::Table.new(colored_context, headers: %w[GROUP NAME STATUS], color_offset: 1)

    assert_equal "\e[37mhldr\e[0m   \e[36mClean\e[0m\n", plain.render([%w[hldr Clean]]).lines.last
    assert_equal "\e[36mwork\e[0m    \e[37mhldr\e[0m   \e[36mClean\e[0m\n",
                 grouped.render([%w[work hldr Clean]]).lines.last
  end

  def test_cells_holding_control_characters_are_made_visible_before_they_are_measured
    table = Slipway::Output::Table.new(plain_context, headers: %w[NAME SUBJECT])

    assert_equal "NAME   SUBJECT\nhldr   fix^[[2Jall\n", table.render([['hldr', "fix\e[2Jall"]])
  end

  def test_light_theme_cycles_its_own_column_colors
    table = Slipway::Output::Table.new(colored_context(theme: 'light'), headers: %w[NAME STATUS])

    assert_equal "\e[1mNAME   STATUS\e[0m\n\e[30mhldr\e[0m   \e[34mClean\e[0m\n", table.render([%w[hldr Clean]])
  end

  def test_the_roles_callback_wins_over_the_column_cycle
    roles = ->(header, value) { :status_success if header == 'STATUS' && value == 'Clean' }
    table = Slipway::Output::Table.new(colored_context, headers: %w[NAME STATUS], roles:)
    expected = "\e[1mNAME   STATUS\e[0m\n" \
               "\e[37mhldr\e[0m   \e[32mClean\e[0m\n" \
               "\e[37mmess\e[0m   \e[36mDirty\e[0m\n"

    assert_equal expected, table.render([%w[hldr Clean], %w[mess Dirty]])
  end

  def test_none_is_painted_muted_before_the_roles_callback_is_asked
    roles = ->(_header, _value) { :status_danger }
    table = Slipway::Output::Table.new(colored_context, headers: %w[NAME BRANCH], show_headers: false, roles:)

    assert_equal "\e[31mhldr\e[0m   \e[90;3m<none>\e[0m\n", table.render([['hldr', nil]])
  end

  def test_print_writes_the_table_to_stdout
    context = plain_context
    table(context).print([%w[hldr main Clean 3d]])

    assert_equal "NAME   BRANCH   STATUS   AGE\nhldr   main     Clean    3d\n", context.out.string
    assert_empty context.err.string
  end

  private

  def table(context, show_headers: true)
    Slipway::Output::Table.new(context, headers: HEADERS, show_headers:)
  end
end
