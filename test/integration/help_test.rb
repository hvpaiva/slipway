# frozen_string_literal: true

require 'test_helper'

class HelpIntegrationTest < Minitest::Test
  include IntegrationHelper

  # The pages the golden suite pins; here the question is which invocations reach them.
  def page(name) = File.read(File.join(GoldenHelper::FIXTURES, 'help', "#{name}.txt"))

  def test_the_root_summary_answers_h_and_an_empty_invocation_and_the_page_every_other_spelling
    with_home do |env|
      root = page('slipway')
      summary = page('slipway.short')

      assert_equal [2, '', summary], slipway(env:)
      assert_equal [0, summary, ''], slipway('-h', env:)
      assert_equal [0, root, ''], slipway('--help', env:)
      assert_equal [0, root, ''], slipway('help', env:)
      assert_equal 'A kubectl-style registry of the git repositories on your machine.', root.lines.first.chomp
    end
  end

  def test_a_verb_page_is_reached_by_flag_or_by_the_help_command
    with_home do |env|
      get = page('slipway-get')

      assert_equal [0, get, ''], slipway('get', '--help', env:)
      assert_equal [0, page('slipway-get.short'), ''], slipway('get', '-h', env:)
      assert_equal [0, get, ''], slipway('help', 'get', env:)
      assert_equal [0, get, ''], slipway('get', 'projects', '-o', 'wide', '--help', env:)
      assert_equal [0, get, ''], slipway('--color=never', 'get', '--help', env:)
    end
  end

  def test_nested_pages_and_global_flags_between_a_group_and_its_subcommand
    with_home do |env|
      view = page('slipway-config-view')

      assert_equal [0, view, ''], slipway('config', 'view', '--help', env:)
      assert_equal [0, view, ''], slipway('help', 'config', 'view', env:)
      assert_equal [0, page('slipway-config'), ''], slipway('config', '--help', env:)
      assert_equal [0, "#{config_file(env)}\n", "The file does not exist; slipway uses its defaults.\n"],
                   slipway('config', '--color=never', 'path', env:)
    end
  end

  def test_an_unknown_command_suggests_a_near_miss_and_points_at_the_root_page
    with_home do |env|
      expected = [2, '', "error: unknown command \"gett\" for \"slipway\"\n\nDid you mean this?\n\tget\n\n" \
                         "Run 'slipway --help' for usage.\n"]

      assert_equal expected, slipway('gett', 'projects', env:)
      assert_equal expected, slipway('help', 'gett', env:)
      assert_equal [2, '', "error: unknown command \"bogus\" for \"slipway config\"\nRun 'slipway config --help' " \
                           "for usage.\n"], slipway('help', 'config', 'bogus', env:)
    end
  end

  def test_an_unknown_flag_names_the_page_of_the_command_it_followed
    with_home do |env|
      assert_equal [2, '', "error: unknown flag: --bogus\nSee 'slipway --help' for usage.\n"], slipway('--bogus', env:)
      assert_equal [2, '', "error: unknown flag: --colour\n\nDid you mean this?\n\t--color\n\n" \
                           "See 'slipway --help' for usage.\n"], slipway('--colour', 'get', 'projects', env:)
      assert_equal [2, '', "error: unknown flag: --selectr\n\nDid you mean this?\n\t--selector\n\n" \
                           "See 'slipway get --help' for usage.\n"], slipway('get', 'projects', '--selectr', 'x', env:)
    end
  end

  def test_an_invalid_global_value_is_a_usage_error
    with_home do |env|
      assert_equal [2, '', 'error: invalid argument "maybe" for --color: must be one of auto, always, ' \
                           "never\nSee 'slipway get --help' for usage.\n"],
                   slipway('--color=maybe', 'get', 'projects', env:)
    end
  end
end
