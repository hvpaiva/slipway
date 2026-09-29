# frozen_string_literal: true

require 'test_helper'
require 'slipway/git'

class GitErrorsTest < Minitest::Test
  def test_a_timeout_of_one_second_is_singular
    messages = [1, 1.0, 60, 0.5].map { Slipway::Git::Timeout.new('/srv/x', seconds: it).message }

    assert_equal ['/srv/x: git did not finish within 1 second', '/srv/x: git did not finish within 1 second',
                  '/srv/x: git did not finish within 60 seconds', '/srv/x: git did not finish within 0.5 seconds'],
                 messages
  end
end
