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

  def test_a_write_stopped_at_the_deadline_is_a_timeout_that_points_at_the_files_it_left
    error = Slipway::Git::WriteTimeout.new('/srv/my repo', seconds: 60)

    assert_kind_of Slipway::Git::Timeout, error
    assert_equal '/srv/my repo: git did not finish within 60 seconds; the files it had written stay in the ' \
                 'working tree', error.message
    assert_equal "Run 'git -C /srv/my\\ repo status' to see them.", error.hint
  end

  def test_the_protocol_hint_names_the_source_it_was_given
    error = Slipway::Git::ProtocolNotAllowed.new('/srv/x', protocol: 'file', source: SOURCE)

    assert_equal "/srv/x: transport 'file' not allowed", error.message
    assert_equal %(Add file to #{SOURCE} to allow it.), error.hint
  end

  def test_each_refusal_of_git_names_itself_as_the_reason
    { Slipway::Git::Busy => 'another git process holds index.lock, or one left it behind',
      Slipway::Git::WouldOverwrite => 'the incoming commits would overwrite untracked files',
      Slipway::Git::WouldLoseChanges => 'the incoming commits would overwrite local changes',
      Slipway::Git::NotFastForward => 'the branch cannot be fast-forwarded' }.each do |klass, detail|
      error = klass.new('/srv/x')

      assert_kind_of Slipway::Git::Blocked, error
      assert_equal [klass.name.split('::').last, "/srv/x: #{detail}"], [error.reason, error.message]
    end
  end

  def test_a_blocked_state_carries_the_reason_it_was_given
    error = Slipway::Git::Blocked.new('/srv/x', 'Detached', 'HEAD is detached at abc1234')

    assert_equal %w[Detached /srv/x], [error.reason, error.path]
    assert_equal '/srv/x: HEAD is detached at abc1234', error.message
  end

  def test_no_hint_suggests_a_transport_the_protocols_setting_refuses
    %w[ext fd].each do |protocol|
      error = Slipway::Git::ProtocolNotAllowed.new('/srv/x', protocol:, source: SOURCE)

      assert_equal "/srv/x: transport '#{protocol}' not allowed", error.message
      assert_nil error.hint
    end
  end
end
