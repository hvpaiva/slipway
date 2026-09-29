# frozen_string_literal: true

require 'test_helper'

class CompletionGoldenTest < Minitest::Test
  include CliHelper
  include GoldenHelper

  REGISTRY = Slipway::Commands.registry(->(_context, _opts) { raise 'completion does not build a runtime' })

  Slipway::CLI::CompletionScripts::SHELLS.each do |shell|
    define_method("test_#{shell}_script") do
      status, out, err = run_cli('completion', shell, registry: REGISTRY)

      assert_equal 0, status
      assert_empty err
      assert_golden(File.join('completion', "slipway.#{shell}"), out)
    end
  end

  def test_every_fixture_belongs_to_a_shell
    skip 'fixtures are being rewritten' if update_golden?

    expected = Slipway::CLI::CompletionScripts::SHELLS.map { "slipway.#{it}" }.sort

    assert_equal expected, Dir.children(File.join(FIXTURES, 'completion')).sort
  end
end
