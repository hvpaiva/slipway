# frozen_string_literal: true

require 'prism'
require 'rake'
require 'test_helper'
require 'tmpdir'

class ContributingTest < Minitest::Test
  ROOT = File.expand_path('../..', __dir__)
  CONTRIBUTING = File.join(ROOT, 'CONTRIBUTING.md')
  TASK = /\A(?:rake )?([a-z][a-z0-9_]*(?::[a-z][a-z0-9_]*)*)\z/
  # The name a task library gives its task when the call names none. bundler-audit's tasks
  # stay out of the table because `rake audit` wraps them.
  LIBRARY_DEFAULTS = { 'RuboCop::RakeTask' => 'rubocop', 'Bundler::Audit::Task' => nil }.freeze

  # Loaded once: the Rakefile defines top-level constants that must not be redefined.
  def self.rake
    @rake ||= load_rakefile
  end

  # raw_load_rakefile raises a load error where load_rakefile would print it and exit, which
  # would end the whole test run without a report.
  def self.load_rakefile(root = ROOT)
    previous = [Rake.application, Rake::TaskManager.record_task_metadata, Dir.pwd]
    Rake::TaskManager.record_task_metadata = true
    Dir.chdir(root)
    Rake.application = Rake::Application.new
    Rake.application.init('rake', [])
    Rake.application.raw_load_rakefile
    Rake.application
  ensure
    Rake.application, Rake::TaskManager.record_task_metadata, directory = previous
    Dir.chdir(directory)
  end

  def test_every_documented_task_exists
    defined = self.class.rake.tasks.map(&:name)

    assert_empty documented_tasks - defined
  end

  def test_every_task_the_project_defines_is_documented
    assert_empty project_tasks - documented_tasks
    assert_includes project_tasks, 'audit'
  end

  def test_every_task_a_task_library_creates_is_documented
    assert_empty library_tasks - documented_tasks
    assert_empty library_tasks - self.class.rake.tasks.map(&:name)
    assert_includes library_tasks, 'rubocop'
  end

  def test_the_library_scan_reads_calls_not_text
    Dir.mktmpdir('slipway-contributing-') do |root|
      FileUtils.mkdir(File.join(root, 'rakelib'))
      File.write(File.join(root, 'Rakefile'), <<~RUBY)
        Minitest::TestTask.create('test:golden') { |t| t.test_globs = ['test/golden/**/*_test.rb'] }
        RuboCop::RakeTask.new
        Bundler::Audit::Task.new
        NOTE = 'YARD::Rake::YardocTask.new(:quoted)'
        HELP = <<~TEXT
          Minitest::TestTask.create(:heredoc)
        TEXT
      RUBY
      File.write(File.join(root, 'rakelib', 'api.rake'), "YARD::Rake::YardocTask.new(:api)\n")

      assert_equal %w[test:golden rubocop api], library_tasks(root)
    end
  end

  def test_a_rakefile_that_fails_to_load_raises_inside_the_test
    Dir.mktmpdir('slipway-contributing-') do |root|
      File.write(File.join(root, 'Rakefile'), "raise 'boom'\n")

      error = assert_raises(RuntimeError) { self.class.load_rakefile(root) }

      assert_equal 'boom', error.message
    end
  end

  private

  def lines = @lines ||= File.readlines(CONTRIBUTING, chomp: true)

  def rows(header)
    start = lines.index(header)
    raise "CONTRIBUTING.md has no table headed #{header}" unless start

    lines.drop(start + 2).take_while { it.start_with?('|') }
  end

  def documented_tasks
    rows('| Task | Runs |').flat_map { it.split('|')[1].scan(/`([^`]+)`/).flatten }.filter_map { TASK.match(it)&.[](1) }
  end

  # A gem's task library adds described tasks of its own; the table lists only ours.
  def project_tasks
    sources = [File.join(ROOT, 'Rakefile:'), File.join(ROOT, 'rakelib', '')]
    self.class.rake.tasks.select { it.comment && it.locations.any? { |location| location.start_with?(*sources) } }
        .map(&:name)
  end

  # A task library records its own gem as the location of the tasks it defines, so the calls
  # that create them are read from the Rakefile and rakelib instead.
  def library_tasks(root = ROOT)
    files = [File.join(root, 'Rakefile'), *Dir.glob(File.join(root, 'rakelib', '**', '*.rake'))]
    files.select { File.file?(it) }.flat_map { calls(Prism.parse_file(it).value) }.filter_map do |call|
      library_task(call)
    end
  end

  def calls(node)
    found = node.compact_child_nodes.flat_map { calls(it) }
    node.is_a?(Prism::CallNode) ? [node, *found] : found
  end

  def library_task(call)
    library = library_constant(call)
    return unless library

    name = call.arguments&.arguments&.first
    return name.unescaped if name.is_a?(Prism::SymbolNode) || name.is_a?(Prism::StringNode)

    LIBRARY_DEFAULTS.fetch(library) { raise KeyError, "add the default task name of #{library} to LIBRARY_DEFAULTS" }
  end

  def library_constant(call)
    receiver = call.receiver
    return unless %i[new create].include?(call.name) && receiver.respond_to?(:full_name)

    receiver.full_name if receiver.full_name.end_with?('Task')
  end
end
