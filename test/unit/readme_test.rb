# frozen_string_literal: true

require 'rake'
require 'test_helper'

class ReadmeTest < Minitest::Test
  ROOT = File.expand_path('../..', __dir__)
  README = File.join(ROOT, 'README.md')
  TASK = /\A(?:rake )?([a-z][a-z0-9_]*(?::[a-z][a-z0-9_]*)*)\z/

  # Loaded once: the Rakefile defines top-level constants that must not be redefined.
  def self.rake
    @rake ||= load_rakefile
  end

  def self.load_rakefile
    previous = [Rake.application, Rake::TaskManager.record_task_metadata, Dir.pwd]
    Rake::TaskManager.record_task_metadata = true
    Dir.chdir(ROOT)
    Rake.application = Rake::Application.new
    Rake.application.init('rake', [])
    Rake.application.load_rakefile
    Rake.application
  ensure
    Rake.application, Rake::TaskManager.record_task_metadata, directory = previous
    Dir.chdir(directory)
  end

  def test_status_table_lists_every_state_in_order
    assert_equal Slipway::State::ROLES.keys, first_cells('| STATUS | Meaning |')
  end

  def test_environment_table_lists_the_man_page_variables_in_order
    assert_equal Slipway::CLI::Manpage::DEFAULT_ENVIRONMENT.keys, first_cells('| Variable | Effect |')
  end

  def test_exit_status_table_lists_every_status_in_order
    assert_equal Slipway::CLI::Manpage::EXIT_STATUSES.keys, first_cells('| Status | Meaning |')
  end

  def test_every_documented_task_exists
    defined = self.class.rake.tasks.map(&:name)

    assert_empty documented_tasks - defined
  end

  def test_every_task_the_project_defines_is_documented
    assert_empty project_tasks - documented_tasks
    assert_includes project_tasks, 'audit'
  end

  private

  def lines = @lines ||= File.readlines(README, chomp: true)

  def first_cells(header) = rows(header).map { it.split('|')[1].strip.delete('`') }

  def rows(header)
    start = lines.index(header)
    raise "README.md has no table headed #{header}" unless start

    lines.drop(start + 2).take_while { it.start_with?('|') }
  end

  def documented_tasks
    rows('| Task | Runs |').flat_map { it.split('|')[1].scan(/`([^`]+)`/).flatten }.filter_map { TASK.match(it)&.[](1) }
  end

  # A gem's task library adds described tasks of its own; the README lists only ours.
  def project_tasks
    sources = [File.join(ROOT, 'Rakefile:'), File.join(ROOT, 'rakelib', '')]
    self.class.rake.tasks.select { it.comment && it.locations.any? { |location| location.start_with?(*sources) } }
        .map(&:name)
  end
end
