# frozen_string_literal: true

require 'test_helper'

class ReadmeTest < Minitest::Test
  ROOT = File.expand_path('../..', __dir__)
  README = File.join(ROOT, 'README.md')

  def test_status_table_lists_every_state_in_order
    assert_equal Slipway::State::ROLES.keys, first_cells('| STATUS | Meaning |')
  end

  def test_drift_tables_list_every_type_and_blocker_in_order
    assert_equal Slipway::Drift::TYPES, first_cells('| Drift | Reported when |')
    assert_equal Slipway::Drift::BLOCKERS.keys, first_cells('| Blocker | Meaning |')
  end

  def test_environment_table_lists_the_man_page_variables_in_order
    assert_equal Slipway::CLI::Manpage::DEFAULT_ENVIRONMENT.keys, first_cells('| Variable | Effect |')
  end

  def test_exit_status_table_lists_every_status_in_order
    assert_equal Slipway::CLI::Manpage::EXIT_STATUSES.keys, first_cells('| Status | Meaning |')
  end

  def test_configuration_example_sets_exactly_the_config_keys
    assert_equal Slipway::Config::KEYS.sort, yaml_block('## Configuration').keys.sort
  end

  private

  def lines = @lines ||= File.readlines(README, chomp: true)

  def first_cells(header) = rows(header).map { it.split('|')[1].strip.delete('`') }

  def rows(header)
    start = lines.index(header)
    raise "README.md has no table headed #{header}" unless start

    lines.drop(start + 2).take_while { it.start_with?('|') }
  end

  def yaml_block(heading)
    start = lines.index(heading)
    raise "README.md has no #{heading} section" unless start

    block = lines.drop(start).drop_while { it != '```yaml' }.drop(1).take_while { it != '```' }
    Psych.safe_load(block.join("\n"))
  end
end
