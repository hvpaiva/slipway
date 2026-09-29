# frozen_string_literal: true

require 'test_helper'
require 'slipway/git'

class GitErrorsTest < Minitest::Test
  SOURCE = '"protocols" in /home/ada/.config/slipway/config.yaml'

  def test_a_timeout_of_one_second_is_singular
    messages = [1, 1.0, 60, 0.5].map { Slipway::Git::Timeout.new('/srv/x', seconds: it).message }

    assert_equal ['/srv/x: git did not finish within 1 second', '/srv/x: git did not finish within 1 second',
                  '/srv/x: git did not finish within 60 seconds', '/srv/x: git did not finish within 0.5 seconds'],
                 messages
  end

  def test_the_protocol_hint_names_the_source_it_was_given
    error = Slipway::Git::ProtocolNotAllowed.new('/srv/x', protocol: 'file', source: SOURCE)

    assert_equal "/srv/x: transport 'file' not allowed", error.message
    assert_equal %(Add file to #{SOURCE} to allow it.), error.hint
  end

  def test_no_hint_suggests_a_transport_the_protocols_setting_refuses
    %w[ext fd].each do |protocol|
      error = Slipway::Git::ProtocolNotAllowed.new('/srv/x', protocol:, source: SOURCE)

      assert_equal "/srv/x: transport '#{protocol}' not allowed", error.message
      assert_nil error.hint
    end
  end
end
