# frozen_string_literal: true

require 'test_helper'

class GlobalsTest < Minitest::Test
  def test_all_lists_the_five_global_options_in_help_order
    assert_equal %w[color group config help version], Slipway::CLI::Globals::ALL.map(&:long)
    assert_predicate Slipway::CLI::Globals::ALL, :frozen?
  end

  def test_keys_match_what_the_runner_reads
    assert_equal %i[color group config help version], Slipway::CLI::Globals::ALL.map(&:key)
  end

  def test_color_takes_an_optional_mode_and_defaults_to_auto
    color = Slipway::CLI::Globals::COLOR

    assert_equal '--color[=WHEN]', color.label
    assert_equal 'always', color.implicit
    assert_equal 'auto', color.default
    assert_equal Slipway::CLI::Style::MODES, color.enum
  end

  def test_short_switches_follow_the_design
    shorts = Slipway::CLI::Globals::ALL.to_h { [it.long, it.short] }

    assert_equal({ 'color' => nil, 'group' => 'n', 'config' => nil, 'help' => 'h', 'version' => 'V' }, shorts)
  end

  def test_only_group_and_config_and_color_take_a_value
    valued = Slipway::CLI::Globals::ALL.reject(&:flag?).map(&:long)

    assert_equal %w[color group config], valued
  end
end
