# frozen_string_literal: true

require 'test_helper'
require 'slipway/git'
require 'slipway/state'

class StateTest < Minitest::Test
  WORDS = %w[Missing NotARepo Unsafe Conflicted Detached Unborn Dirty Gone Diverged Ahead Behind Clean Unknown].freeze

  def test_words_are_listed_in_precedence_order
    assert_equal WORDS, Slipway::State::WORDS
  end

  def test_clean_repository
    assert_equal 'Clean', derive
    assert_equal 'Clean', derive(upstream: 'origin/main', ahead: 0, behind: 0)
    assert_equal 'Clean', derive(stashes: 3)
  end

  def test_position_against_upstream
    assert_equal 'Ahead', derive(upstream: 'origin/main', ahead: 1, behind: 0)
    assert_equal 'Behind', derive(upstream: 'origin/main', ahead: 0, behind: 2)
    assert_equal 'Diverged', derive(upstream: 'origin/main', ahead: 1, behind: 1)
    assert_equal 'Gone', derive(upstream: 'origin/feature', upstream_gone: true)
  end

  def test_dirty_outranks_the_position
    assert_equal 'Dirty', derive(staged: 1)
    assert_equal 'Dirty', derive(unstaged: 1, upstream: 'origin/main', ahead: 1, behind: 0)
    assert_equal 'Dirty', derive(untracked: 1, upstream: 'origin/main', ahead: 1, behind: 1)
    assert_equal 'Dirty', derive(untracked: 1, upstream: 'origin/feature', upstream_gone: true)
  end

  def test_unborn_outranks_dirty
    assert_equal 'Unborn', derive(head: nil)
    assert_equal 'Unborn', derive(head: nil, staged: 1)
  end

  def test_detached_outranks_unborn_and_dirty
    assert_equal 'Detached', derive(branch: nil)
    assert_equal 'Detached', derive(branch: nil, head: nil)
    assert_equal 'Detached', derive(branch: nil, unstaged: 1, upstream: 'origin/main', ahead: 1, behind: 0)
  end

  def test_conflicted_outranks_everything
    assert_equal 'Conflicted', derive(conflicted: 1)
    assert_equal 'Conflicted', derive(conflicted: 1, branch: nil, staged: 2, untracked: 1)
  end

  def test_errors_about_the_path_get_their_own_word
    assert_equal 'Missing', Slipway::State.for_error(Slipway::Git::MissingPath.new('/x'))
    assert_equal 'NotARepo', Slipway::State.for_error(Slipway::Git::NotARepository.new('/x'))
    assert_equal 'Unsafe', Slipway::State.for_error(Slipway::Git::UnsafeRepository.new('/x'))
  end

  def test_every_other_failure_is_unknown
    assert_equal 'Unknown', Slipway::State.for_error(Slipway::Git::NotInstalled.new('/x'))
    assert_equal 'Unknown', Slipway::State.for_error(Slipway::Git::Timeout.new('/x'))
    assert_equal 'Unknown', Slipway::State.for_error(Slipway::Git::Error.new('/x', 'git exited with status 128'))
    assert_equal 'Unknown', Slipway::State.for_error(RuntimeError.new('boom'))
  end

  def test_roles_follow_the_theme
    assert_equal :status_success, Slipway::State.role('Clean')
    warning = %w[Dirty Ahead Behind Diverged Detached Gone Unborn]
    danger = %w[Missing NotARepo Unsafe Conflicted]

    assert_equal(%i[status_warning] * 7, warning.map { Slipway::State.role(it) })
    assert_equal(%i[status_danger] * 4, danger.map { Slipway::State.role(it) })
    assert_equal :muted, Slipway::State.role('Unknown')
  end

  def test_every_word_has_a_role_and_nothing_else_does
    roles = Slipway::State::WORDS.map { Slipway::State.role(it) }

    assert_equal Slipway::State::WORDS.size, roles.size
    assert_raises(KeyError) { Slipway::State.role('Running') }
  end

  private

  def derive(head: 'abc1234', **fields) = Slipway::State.derive(Slipway::Git::Status.new(head:, **fields))
end
