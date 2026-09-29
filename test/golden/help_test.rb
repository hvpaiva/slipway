# frozen_string_literal: true

require 'test_helper'

# The help page of the root and of every visible command, compared to test/fixtures/golden/help.
class HelpGoldenTest < Minitest::Test
  include CliHelper
  include GoldenHelper

  # Help never runs a verb, so the runtime factory is never called.
  REGISTRY = Slipway::Commands.registry(->(_context, _opts) { raise 'help does not build a runtime' })

  # Every command path the registry exposes, the root first, groups before their children.
  def self.paths(command = REGISTRY.root, path = [])
    [path, *command.visible_subcommands.flat_map { paths(it, [*path, it.name]) }]
  end

  paths.each do |path|
    define_method("test_help_of_#{path.empty? ? 'root' : path.join('_')}") do
      status, out, err = run_cli(*path, '--help', registry: REGISTRY)

      assert_equal 0, status
      assert_empty err
      assert_golden(File.join('help', "#{[REGISTRY.program, *path].join('-')}.txt"), out)
    end
  end

  def test_every_fixture_belongs_to_a_command
    skip 'fixtures are being rewritten' if update_golden?

    expected = self.class.paths.map { "#{[REGISTRY.program, *it].join('-')}.txt" }.sort

    assert_equal expected, Dir.children(File.join(FIXTURES, 'help')).sort
  end
end
