# frozen_string_literal: true

require 'test_helper'

class HelpGoldenTest < Minitest::Test
  include CliHelper
  include GoldenHelper

  # Help never runs a verb, so the runtime factory is never called.
  REGISTRY = Slipway::Commands.registry(->(_context, _opts) { raise 'help does not build a runtime' })

  def self.paths(command = REGISTRY.root, path = [])
    [path, *command.visible_subcommands.flat_map { paths(it, [*path, it.name]) }]
  end

  FORMS = { '--help' => '.txt', '-h' => '.short.txt' }.freeze

  paths.product(FORMS.to_a).each do |path, (flag, extension)|
    define_method("test_#{flag.delete('-')}_of_#{path.empty? ? 'root' : path.join('_')}") do
      status, out, err = run_cli(*path, flag, registry: REGISTRY)

      assert_equal 0, status
      assert_empty err
      assert_golden(File.join('help', "#{[REGISTRY.program, *path].join('-')}#{extension}"), out)
    end
  end

  def test_every_fixture_belongs_to_a_command
    skip 'fixtures are being rewritten' if update_golden?

    expected = self.class.paths.product(FORMS.values).map { |path, ext| "#{[REGISTRY.program, *path].join('-')}#{ext}" }
                   .sort

    assert_equal expected, Dir.children(File.join(FIXTURES, 'help')).sort
  end
end
