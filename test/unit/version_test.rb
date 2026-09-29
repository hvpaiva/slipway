# frozen_string_literal: true

require 'test_helper'

# The version constant is what the gemspec, the tag and `slipway version` agree on.
class VersionTest < Minitest::Test
  def test_version_is_a_release_version
    assert Gem::Version.correct?(Slipway::VERSION)
    refute_predicate Gem::Version.new(Slipway::VERSION), :prerelease?
  end
end
