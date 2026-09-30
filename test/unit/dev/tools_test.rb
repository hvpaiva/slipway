# frozen_string_literal: true

require 'prism'
require 'test_helper'
require 'tmpdir'
require_relative '../../../rakelib/support/tools'

class ToolsTest < Minitest::Test
  ROOT = File.expand_path('../../..', __dir__)
  SETUP = File.join(ROOT, 'bin', 'setup')

  def test_every_tool_a_rake_task_requires_is_pinned_in_mise_toml_or_reported_by_bin_setup
    required = required_tools

    assert_empty required - Tools.pinned.keys - reported_tools
    assert_includes required, 'typos'
    assert_includes required, 'groff'
  end

  def test_pinned_reads_the_tools_table_and_nothing_else
    Dir.mktmpdir('slipway-tools-') do |dir|
      path = File.join(dir, 'mise.toml')
      File.write(path, <<~TOML)
        min_version = "2026.1.0"

        [tools]
        # The version CI runs.
        ruby = "4.0.7"
        typos = "1.50.3" # trailing comment

        [settings]
        experimental = "true"
      TOML

      assert_equal({ 'ruby' => '4.0.7', 'typos' => '1.50.3' }, Tools.pinned(path))
    end
  end

  def test_a_missing_pinned_tool_names_the_mise_command
    assert_equal 'typos is not installed; install the version mise.toml pins with: mise install typos',
                 Tools.missing('typos', { 'typos' => '1.50.3' }, installed_by_mise: false)
  end

  def test_a_pinned_tool_mise_installed_off_path_says_to_activate_mise
    assert_equal 'typos is installed by mise but not on PATH; activate mise in your shell (mise activate --help)',
                 Tools.missing('typos', { 'typos' => '1.50.3' }, installed_by_mise: true)
  end

  def test_a_missing_system_tool_names_the_package_managers
    assert_equal 'groff is not installed; install it with your package manager (pacman, apt or brew)',
                 Tools.missing('groff', { 'typos' => '1.50.3' })
  end

  private

  def nodes(node) = [node, *node.compact_child_nodes.flat_map { nodes(it) }]

  def required_tools
    files = [File.join(ROOT, 'Rakefile'), *Dir.glob(File.join(ROOT, 'rakelib', '**', '*.rake'))]
    calls = files.flat_map { nodes(Prism.parse_file(it).value) }.grep(Prism::CallNode)
    calls.select { it.name == :require_tool }.filter_map do |call|
      argument = call.arguments&.arguments&.first
      argument.unescaped if argument.is_a?(Prism::StringNode)
    end.uniq
  end

  def reported_tools = File.read(SETUP).scan(/^report (\S+) /).flatten
end
