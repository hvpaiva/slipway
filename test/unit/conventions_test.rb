# frozen_string_literal: true

require 'prism'
require 'test_helper'
require 'tmpdir'

# The code rules read syntax trees, so strings, symbols, heredocs and comments never count as calls.
module SyntaxRules
  # Kernel and Process answer these with an explicit receiver too.
  KERNEL_RECEIVERS = %i[Kernel Process].freeze
  SPAWN_CALLS = %i[system spawn exec].freeze
  STREAM_CALLS = %i[puts print printf putc warn p pp].freeze
  # Reading $stdin is allowed: apply -f - takes the manifest from it.
  STREAM_GLOBALS = %i[$stdout $stderr].freeze
  STREAM_CONSTANTS = %i[STDOUT STDERR].freeze

  def nodes(node) = [node, *node.compact_child_nodes.flat_map { nodes(it) }]

  def spawn?(node)
    case node
    when Prism::XStringNode, Prism::InterpolatedXStringNode then true
    when Prism::CallNode then node.name == :popen || (kernel_call?(node) && SPAWN_CALLS.include?(node.name))
    else constant?(node, :Open3)
    end
  end

  def yaml_write?(node)
    node.is_a?(Prism::CallNode) &&
      (node.name == :to_yaml || (%i[dump safe_dump].include?(node.name) && constant?(node.receiver, :YAML, :Psych)))
  end

  def stream?(node)
    case node
    when Prism::CallNode then kernel_call?(node) && STREAM_CALLS.include?(node.name)
    when Prism::GlobalVariableReadNode, Prism::GlobalVariableWriteNode then STREAM_GLOBALS.include?(node.name)
    else constant?(node, *STREAM_CONSTANTS)
    end
  end

  def warning_prefix?(node) = node.is_a?(Prism::StringNode) && node.unescaped.start_with?('warning:')

  def kernel_call?(call) = call.receiver.nil? || constant?(call.receiver, *KERNEL_RECEIVERS)

  def constant?(node, *names)
    (node.is_a?(Prism::ConstantReadNode) || node.is_a?(Prism::ConstantPathNode)) && names.include?(node.name)
  end
end

class ConventionsTest < Minitest::Test
  include SyntaxRules

  ROOT = File.expand_path('../..', __dir__)
  LIB = File.join(ROOT, 'lib')
  SHIPPED_DIRECTORIES = %w[lib/ exe/ man/].freeze
  # .yardopts ships because rubydoc.info renders the API documentation from the gem.
  SHIPPED_DOCUMENTS = %w[README.md CHANGELOG.md LICENSE.txt .yardopts].freeze
  ASCII_TREES = %w[lib exe bin rakelib test/fixtures/golden test/fixtures/man].freeze
  TEST_TREES = %w[test/unit test/integration test/golden].freeze

  # Paths are relative to lib/slipway.
  SPAWNERS = [
    'git/runner.rb', # the one place that runs git, with its hardened environment and deadline
    'editor.rb'      # hands the terminal to the user's editor for `slipway edit`
  ].freeze

  YAML_WRITERS = [
    'yaml.rb',    # the one YAML writer: Psych.safe_dump without line folding
    'manifest.rb' # re-emits an already parsed Psych node so safe_load can check it; it writes no file
  ].freeze

  # Context wraps the process streams; everything else prints through it.
  STREAM_OWNERS = ['cli/context.rb'].freeze

  # Output.warning neutralizes the message after the prefix, so no other file writes the prefix.
  WARNING_WRITERS = ['output.rb'].freeze

  CLI = %w[cli.rb cli/].freeze
  DOMAIN = %w[paths.rb config.rb editor.rb names.rb labels.rb selector.rb field_selector.rb resources.rb
              schema.rb manifest.rb store.rb scanner.rb yaml.rb error.rb git.rb git/ state.rb drift.rb plan.rb
              rollout.rb version.rb].freeze
  OUTPUT = %w[output.rb output/].freeze
  UPPER_LAYERS = %w[commands.rb commands/ views.rb views/ runtime.rb inspector.rb fetcher.rb sync.rb rollback.rb
                    pool.rb slipway.rb].freeze
  CLI_EXTERNAL_EDGES = { 'cli/errors.rb' => ['error.rb'] }.freeze

  def test_the_gem_has_no_runtime_dependencies
    assert_empty spec.runtime_dependencies
  end

  def test_the_gem_ships_only_code_man_pages_the_three_documents_and_yardopts
    stray = spec.files.reject { it.start_with?(*SHIPPED_DIRECTORIES) || SHIPPED_DOCUMENTS.include?(it) }

    assert_empty stray, 'add these to the denylist in slipway.gemspec or to this allowlist'
    assert_includes spec.files, 'lib/slipway.rb'
  end

  def test_lib_requires_its_own_files_with_require_relative
    offenders = lib_files.flat_map { locations(it, gem_requires(it)) }

    assert_empty offenders
  end

  def test_shipped_code_scripts_and_fixtures_are_ascii
    files = ASCII_TREES.flat_map { Dir.glob("#{it}/**/*", base: ROOT) }
                       .select { File.file?(File.join(ROOT, it)) }

    assert_empty(files.reject { File.binread(File.join(ROOT, it)).ascii_only? })
    assert_operator files.size, :>, 50
  end

  def test_only_the_git_runner_and_the_editor_spawn_processes
    assert_equal(SPAWNERS.sort, files_where { spawn?(it) })
  end

  def test_only_the_yaml_module_and_the_manifest_emit_yaml
    assert_equal(YAML_WRITERS.sort, files_where { yaml_write?(it) })
  end

  def test_only_the_context_touches_the_standard_streams
    assert_equal(STREAM_OWNERS, files_where { stream?(it) })
  end

  def test_only_the_output_helper_writes_a_warning_line
    assert_equal(WARNING_WRITERS, files_where { warning_prefix?(it) })
  end

  def test_the_spawn_rule_reads_calls_not_text
    caught = { 'system.rb' => "def self.shell_out = system 'true'\n", 'backticks.rb' => "def self.day = `date`\n",
               'percent_x.rb' => "def self.day = %x(date)\n", 'process.rb' => "Process.spawn('true')\n",
               'exec.rb' => "exec('true')\n", 'open3.rb' => "Open3.capture3('git', 'status')\n",
               'popen.rb' => "IO.popen(%w[git status], &:read)\n" }
    ignored = <<~RUBY
      NOTE = 'system spawn exec Open3 popen'
      KEYS = { system: 1, exec: 2 }.freeze
      HELP = <<~TEXT
        run system('true') or `date`
      TEXT
      runner.exec('status')
    RUBY

    assert_equal caught.keys.sort, scratch_files_where(caught.merge('ignored.rb' => ignored)) { spawn?(it) }
  end

  def test_the_yaml_rule_reads_calls_not_text
    caught = { 'to_yaml.rb' => "hash.to_yaml\n", 'dump.rb' => "YAML.dump(hash)\n",
               'safe_dump.rb' => "YAML.safe_dump(hash)\n", 'psych.rb' => "Psych.safe_dump(hash, line_width: -1)\n" }
    ignored = <<~RUBY
      Psych.safe_load(text)
      Yaml.dump(hash)
      NOTE = 'to_yaml and YAML.dump'
      HELP = <<~TEXT
        Psych.dump(hash)
      TEXT
    RUBY

    assert_equal caught.keys.sort, scratch_files_where(caught.merge('ignored.rb' => ignored)) { yaml_write?(it) }
  end

  def test_the_stream_rule_reads_calls_not_text
    caught = { 'puts.rb' => "def self.show(list) = list.each { puts it }\n", 'warn.rb' => "ok ? warn(1) : 2\n",
               'pp.rb' => "pp(value)\n", 'print.rb' => "Kernel.print 'x'\n", 'stderr.rb' => "$stderr.write('x')\n",
               'stdout.rb' => "STDOUT.sync = true\n", 'swap.rb' => "$stdout = StringIO.new\n" }
    ignored = <<~RUBY
      RULE_TEXT = 'names must not start with STDOUT'
      WIDTHS = {
        print: 63, warn: 60
      }.freeze
      HELP = <<~TEXT
        puts 'x' to $stdout
      TEXT
      context.puts('x')
    RUBY

    assert_equal caught.keys.sort, scratch_files_where(caught.merge('ignored.rb' => ignored)) { stream?(it) }
  end

  def test_the_warning_rule_reads_strings_not_comments_or_symbols
    caught = { 'literal.rb' => "context.warn('warning: x')\n", 'interpolated.rb' => %(warn("warning: \#{text}")\n),
               'painted.rb' => %(warn("\#{paint_err(:warning, 'warning:')} x")\n) }
    ignored = "# warning: x\nTHEME = { warning: '33' }.freeze\nNOTE = 'a warning: x'\nOutput.warning(context, x)\n"

    assert_equal caught.keys.sort, scratch_files_where(caught.merge('ignored.rb' => ignored)) { warning_prefix?(it) }
  end

  def test_the_require_rules_read_calls_not_text
    source = <<~RUBY
      require_relative('../commands')
      require_relative 'cli/style' if defined?(Style)
      NOTE = "require_relative 'quoted' and require 'slipway/quoted'"
      HELP = <<~TEXT
        require_relative 'heredoc'
      TEXT
      require('slipway/store')
      load File.join(ROOT, 'rakelib/support/changelog.rb')
    RUBY

    scratch('lib.rb' => source) do |(lib)|
      assert_equal %w[../commands.rb cli/style.rb].map { File.expand_path(it, File.dirname(lib)) },
                   require_targets(lib)
      assert_equal ["#{lib}:7", "#{lib}:8"], locations(lib, gem_requires(lib)) + locations(lib, outside_loads(lib))
    end
  end

  def test_test_files_that_define_tests_end_in_test_rb
    defining = TEST_TREES.flat_map { Dir.glob("#{it}/**/*.rb", base: ROOT) }.select do |file|
      File.read(File.join(ROOT, file)).match?(/^\s*class \S+ < Minitest::Test\b/)
    end

    assert_empty(defining.reject { it.end_with?('_test.rb') }, 'rake test only runs *_test.rb')
    assert_operator defining.size, :>, 50
  end

  def test_every_file_belongs_to_exactly_one_layer
    layers = [CLI, DOMAIN, OUTPUT, UPPER_LAYERS]
    misplaced = lib_files.map { slipway_path(it) }.reject { |path| layers.one? { layer?(path, it) } }

    assert_empty misplaced
  end

  def test_cli_and_the_domain_never_require_the_command_layer
    offenders = require_edges.select do |from, to|
      (layer?(from, CLI) || layer?(from, DOMAIN)) && layer?(to, UPPER_LAYERS)
    end

    assert_empty(offenders.map { it.join(' -> ') })
  end

  def test_output_never_requires_views_commands_or_the_runtime
    offenders = require_edges.select { |from, to| layer?(from, OUTPUT) && layer?(to, UPPER_LAYERS) }

    assert_empty(offenders.map { it.join(' -> ') })
  end

  def test_cli_requires_nothing_outside_itself_but_the_error_root
    external = require_edges.select { |from, to| layer?(from, CLI) && !layer?(to, CLI) }

    assert_equal(CLI_EXTERNAL_EDGES.flat_map { |from, targets| targets.map { [from, it] } }, external)
  end

  def test_lib_requires_nothing_outside_lib
    targets = lib_files.flat_map { |file| require_targets(file) }
    outside = targets.reject { it.start_with?("#{LIB}/") && File.file?(it) }
    loads = lib_files.flat_map { locations(it, outside_loads(it)) }

    assert_empty outside
    assert_empty loads
    assert_operator targets.size, :>, 100
  end

  private

  def spec
    @spec ||= Dir.chdir(ROOT) { Gem::Specification.load('slipway.gemspec') }
  end

  def lib_files = Dir.glob('**/*.rb', base: LIB).sort.map { File.join(LIB, it) }

  # The layers name lib/slipway.rb as slipway.rb, so both prefixes are dropped.
  def slipway_path(file) = file.delete_prefix("#{LIB}/").delete_prefix('slipway/')

  def tree(file) = (@trees ||= {})[file] ||= nodes(Prism.parse_file(file).value)

  def files_where(files = lib_files, &) = files.select { tree(it).any?(&) }.map { slipway_path(it) }.sort

  def scratch(sources)
    Dir.mktmpdir('slipway-conventions-') do |dir|
      yield(sources.map { |name, source| File.join(dir, name).tap { File.write(it, source) } })
    end
  end

  def scratch_files_where(sources, &)
    scratch(sources) { |files| files_where(files, &).map { File.basename(it) } }
  end

  def calls(file, *names)
    tree(file).select { it.is_a?(Prism::CallNode) && it.receiver.nil? && names.include?(it.name) }
  end

  def locations(file, found) = found.map { "#{slipway_path(file)}:#{it.location.start_line}" }

  def string_argument(call)
    argument = call.arguments&.arguments&.first
    argument.unescaped if argument.is_a?(Prism::StringNode)
  end

  def gem_requires(file) = calls(file, :require).select { string_argument(it)&.start_with?('slipway') }

  # Any string inside the call counts, so File.join(ROOT, 'rakelib/...') is caught too.
  def outside_loads(file)
    calls(file, :require, :require_relative, :load, :autoload).select do |call|
      nodes(call).grep(Prism::StringNode).any? { it.unescaped.match?(%r{\b(rakelib|bin)/}) }
    end
  end

  def require_targets(file)
    calls(file, :require_relative).filter_map { string_argument(it) }.map do |target|
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
