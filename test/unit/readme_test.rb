# frozen_string_literal: true

require 'test_helper'

class ReadmeTest < Minitest::Test
  ROOT = File.expand_path('../..', __dir__)
  README = File.join(ROOT, 'README.md')
  RESULTS = '| Result | Meaning |'

  def test_status_table_lists_every_state_in_order
    assert_equal Slipway::State::ROLES.keys, first_cells('| STATUS | Meaning |')
  end

  def test_drift_tables_list_every_type_and_blocker_in_order
    assert_equal Slipway::Drift::TYPES, first_cells('| Drift | Reported when |')
    assert_equal Slipway::Drift::BLOCKERS.keys, first_cells('| Blocker | Meaning |')
  end

  def test_environment_table_lists_the_man_page_variables_in_order
    assert_equal Slipway::Commands::Manual::ENVIRONMENT.keys, first_cells('| Variable | Effect |')
  end

  def test_exit_status_table_lists_every_status_in_order
    assert_equal Slipway::Commands::Manual::EXIT_STATUSES.keys, first_cells('| Status | Meaning |')
  end

  def test_result_tables_list_every_result_word_in_order
    assert_equal Slipway::Commands::Fetch::ROLES.keys, result_words('### Fetching')
    assert_equal Slipway::Commands::SyncCommand::ROLES.keys, result_words('### Syncing')
    assert_equal Slipway::Commands::RolloutCommand::Undo::ROLES.keys, result_words('### Rolling back')
  end

  # The words a fetch puts in parentheses: its own reasons and the states in which git could not
  # read the repository.
  def test_fetch_table_names_every_reason_a_fetch_gives
    unreadable = [Slipway::Git::MissingPath, Slipway::Git::NotARepository, Slipway::Git::UnsafeRepository,
                  Slipway::Git::Error].map { Slipway::State.for_error(it.allocate) }
    reasons = [*Slipway::Fetcher::REASONS.values, Slipway::Fetcher::NO_REMOTE, *unreadable]
    documented = rows(RESULTS, after: '### Fetching').flat_map { it.scan(/`([A-Z][A-Za-z]+)`|\(([A-Z][A-Za-z]+)\)`/) }

    assert_equal reasons.uniq.sort, documented.flatten.compact.uniq.sort - ['Reason']
  end

  def test_field_selector_sentence_lists_every_field
    sentence = /Projects support (?<projects>.*?); groups support (?<groups>.*?)\.(?: |\z)/.match(lines.join(' '))
    fields = ->(part) { sentence[part].scan(/`([^`]+)`/).flatten }

    assert_equal Slipway::Views::Project::FIELDS.keys, fields.call(:projects)
    assert_equal Slipway::Views::Group::FIELDS.keys, fields.call(:groups)
  end

  def test_configuration_example_sets_exactly_the_config_keys
    assert_equal Slipway::Config::KEYS.sort, yaml_block('## Configuration').keys.sort
  end

  private

  def lines = @lines ||= File.readlines(README, chomp: true)

  def first_cells(header) = rows(header).map { it.split('|')[1].strip.delete('`') }

  # +after+ names the heading the table sits under, for a header several tables share.
  def rows(header, after: nil)
    from = after ? lines.index(after) : 0
    raise "README.md has no #{after} section" unless from

    start = lines.each_index.find { it > from && lines[it] == header }
    raise "README.md has no table headed #{header}#{" under #{after}" if after}" unless start

    lines.drop(start + 2).take_while { it.start_with?('|') }
  end

  # The word a result line starts with, without the reason a table row gives it in parentheses.
  def result_words(section)
    rows(RESULTS, after: section).map { it.split('|')[1].strip.delete('`').sub(/ \(.*\)\z/, '') }
  end

  def yaml_block(heading)
    start = lines.index(heading)
    raise "README.md has no #{heading} section" unless start

    block = lines.drop(start).drop_while { it != '```yaml' }.drop(1).take_while { it != '```' }
    Psych.safe_load(block.join("\n"))
  end
end
