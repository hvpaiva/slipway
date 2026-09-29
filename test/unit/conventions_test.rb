# frozen_string_literal: true

require 'test_helper'

class ConventionsTest < Minitest::Test
  ROOT = File.expand_path('../..', __dir__)
  LIB = File.join(ROOT, 'lib')
  SHIPPED_DIRECTORIES = %w[lib/ exe/ man/].freeze
  SHIPPED_DOCUMENTS = %w[README.md CHANGELOG.md LICENSE.txt].freeze
  ASCII_TREES = %w[lib exe bin rakelib test/fixtures/golden].freeze
  TEST_TREES = %w[test/unit test/integration test/golden].freeze

  SPAWN = /\bOpen3\b|\bspawn\(|popen|\bsystem\(/
  # Paths are relative to lib/slipway.
  SPAWNERS = [
    'git/runner.rb', # the one place that runs git, with its hardened environment and deadline
    'editor.rb'      # hands the terminal to the user's editor for `slipway edit`
  ].freeze

  YAML_WRITE = /to_yaml|Psych\.(safe_)?dump|YAML\.dump/
  YAML_WRITERS = [
    'yaml.rb',    # the one YAML writer: Psych.safe_dump without line folding
    'manifest.rb' # re-emits an already parsed Psych node so safe_load can check it; it writes no file
  ].freeze

  STREAMS = /\$stderr|\$stdout|STDERR|STDOUT|^\s*(puts|warn|print)\b/
  # Context wraps the process streams; everything else prints through it.
  STREAM_OWNERS = ['cli/context.rb'].freeze

  DOMAIN = %w[paths.rb config.rb editor.rb names.rb labels.rb selector.rb resources.rb manifest.rb
              store.rb yaml.rb error.rb git.rb git/ state.rb].freeze
  UPPER_LAYERS = %w[commands.rb commands/ views.rb views/ runtime.rb inspector.rb slipway.rb].freeze
  CLI_EXTERNAL_EDGES = { 'cli/errors.rb' => ['error.rb'] }.freeze

  def test_the_gem_has_no_runtime_dependencies
    assert_empty spec.runtime_dependencies
  end

  def test_the_gem_ships_only_code_man_pages_and_the_three_documents
    stray = spec.files.reject { it.start_with?(*SHIPPED_DIRECTORIES) || SHIPPED_DOCUMENTS.include?(it) }

    assert_empty stray, 'add these to the denylist in slipway.gemspec or to this allowlist'
    assert_includes spec.files, 'lib/slipway.rb'
  end

  def test_lib_requires_its_own_files_with_require_relative
    offenders = code_lines(lib_files).select { |_, line| line.match?(/^\s*require ['"]slipway/) }

    assert_empty offenders.map(&:first)
  end

  def test_shipped_code_scripts_and_fixtures_are_ascii
    files = ASCII_TREES.flat_map { Dir.glob("#{it}/**/*", base: ROOT) }
                       .select { File.file?(File.join(ROOT, it)) }

    assert_empty(files.reject { File.binread(File.join(ROOT, it)).ascii_only? })
    assert_operator files.size, :>, 50
  end

  def test_only_the_git_runner_and_the_editor_spawn_processes
    assert_equal SPAWNERS.sort, files_matching(SPAWN)
  end

  def test_only_the_yaml_module_and_the_manifest_emit_yaml
    assert_equal YAML_WRITERS.sort, files_matching(YAML_WRITE)
  end

  def test_only_the_context_touches_the_standard_streams
    assert_equal STREAM_OWNERS, files_matching(STREAMS)
  end

  def test_test_files_that_define_tests_end_in_test_rb
    defining = TEST_TREES.flat_map { Dir.glob("#{it}/**/*.rb", base: ROOT) }.select do |file|
      File.read(File.join(ROOT, file)).match?(/^\s*class \S+ < Minitest::Test\b/)
    end

    assert_empty(defining.reject { it.end_with?('_test.rb') }, 'rake test only runs *_test.rb')
    assert_operator defining.size, :>, 50
  end

  def test_cli_and_the_domain_never_require_the_command_layer
    offenders = require_edges.select do |from, to|
      (from.start_with?('cli/') || layer?(from, DOMAIN)) && layer?(to, UPPER_LAYERS)
    end

    assert_empty(offenders.map { it.join(' -> ') })
  end

  def test_cli_requires_nothing_outside_itself_but_the_error_root
    external = require_edges.select { |from, to| from.start_with?('cli/') && !to.start_with?('cli/') }

    assert_equal(CLI_EXTERNAL_EDGES.flat_map { |from, targets| targets.map { [from, it] } }, external)
  end

  def test_lib_requires_nothing_outside_lib
    targets = lib_files.flat_map { |file| require_targets(file) }
    outside = targets.reject { it.start_with?("#{LIB}/") && File.file?(it) }
    loads = code_lines(lib_files).select { |_, line| line.match?(%r{\b(require|load)\b.*\b(rakelib|bin)/}) }

    assert_empty outside
    assert_empty loads.map(&:first)
    assert_operator targets.size, :>, 100
  end

  private

  def spec
    @spec ||= Dir.chdir(ROOT) { Gem::Specification.load('slipway.gemspec') }
  end

  def lib_files = Dir.glob('**/*.rb', base: LIB).sort.map { File.join(LIB, it) }

  def slipway_path(file) = file.delete_prefix("#{LIB}/slipway/")

  # Comment lines are skipped, so prose about $stdout is allowed.
  def code_lines(files)
    files.flat_map do |file|
      File.readlines(file, chomp: true).each_with_index.filter_map do |line, index|
        ["#{slipway_path(file)}:#{index + 1}", line] unless line.match?(/\A\s*#/)
      end
    end
  end

  def files_matching(pattern)
    code_lines(lib_files).filter_map { |location, line| location.split(':').first if line.match?(pattern) }.uniq.sort
  end

  def require_targets(file)
    File.read(file).scan(/^\s*require_relative ['"]([^'"]+)['"]/).map do |(target)|
      File.expand_path("#{target.delete_suffix('.rb')}.rb", File.dirname(file))
    end
  end

  def require_edges
    lib_files.select { it.start_with?("#{LIB}/slipway/") }.flat_map do |file|
      require_targets(file).map { [slipway_path(file), slipway_path(it)] }
    end
  end

  def layer?(path, layer) = layer.any? { it.end_with?('/') ? path.start_with?(it) : path == it }
end
