# frozen_string_literal: true

require 'test_helper'
require 'tmpdir'
require_relative '../../../rakelib/support/golden'

class GoldenFixturesTest < Minitest::Test
  REGISTRY = Slipway::Commands.registry(->(_context, _opts) { raise 'fixtures do not build a runtime' })
  SHELLS = Slipway::CLI::CompletionScripts::SHELLS

  def test_expected_matches_the_checked_in_fixtures
    fixtures = Dir.glob('**/*', base: GoldenHelper::FIXTURES).select { File.file?(File.join(GoldenHelper::FIXTURES, it)) }

    assert_equal fixtures.sort, GoldenFixtures.expected(REGISTRY, SHELLS).sort
  end

  def test_remove_orphans_deletes_only_unlisted_files
    Dir.mktmpdir('slipway-golden-') do |root|
      FileUtils.mkdir_p(File.join(root, 'help'))
      %w[help/slipway.txt help/slipway-gone.txt].each { File.write(File.join(root, it), '') }

      assert_equal ['help/slipway-gone.txt'], GoldenFixtures.remove_orphans(root, ['help/slipway.txt'])
      assert_equal ['slipway.txt'], Dir.children(File.join(root, 'help'))
    end
  end
end
