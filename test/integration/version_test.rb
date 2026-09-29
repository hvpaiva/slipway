# frozen_string_literal: true

require 'test_helper'

class VersionIntegrationTest < Minitest::Test
  include IntegrationHelper

  LINE = "slipway #{Slipway::VERSION} (ruby #{RUBY_VERSION}) [#{Gem::Platform.local}]\n".freeze

  def test_the_version_command_and_both_flags_print_the_same_line
    with_home do |env|
      assert_equal [0, LINE, ''], slipway('version', env:)
      assert_equal [0, LINE, ''], slipway('--version', env:)
      assert_equal [0, LINE, ''], slipway('-V', env:)
      assert_equal [0, LINE, ''], slipway('get', 'projects', '-V', env:)
      assert_match(/\Aslipway \d+\.\d+\.\d+ \(ruby \d+\.\d+\.\d+\) \[\S+\]\n\z/, LINE)
    end
  end
end
