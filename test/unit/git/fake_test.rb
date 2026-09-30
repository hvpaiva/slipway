# frozen_string_literal: true

require 'test_helper'
require 'slipway/git'

class GitFakeTest < Minitest::Test
  STATUS = Slipway::Git::Status.new(head: 'abc1234', untracked: 1)
  COMMIT = Slipway::Git::Commit.new(sha: 'a' * 40, short: 'aaaaaaa', time: Time.at(0).utc,
                                    author: 'Fixture', email: 'fixture@example.com', subject: 'initial commit')
  FETCHED = Slipway::Git::FetchResult.new(updates: [['refs/remotes/origin/main', 'a' * 40, 'b' * 40]])
  FETCHED_AT = Time.utc(2026, 9, 29, 11, 0, 0)

  def setup
    @fake = Slipway::Git::Fake.new
  end

  def test_add_registers_the_three_answers_for_a_path
    @fake.add('/srv/hldr', status: STATUS, commit: COMMIT, remote: 'git@github.com:hvpaiva/hldr.git')

    assert_equal STATUS, @fake.status('/srv/hldr')
    assert_equal COMMIT, @fake.last_commit('/srv/hldr')
    assert_equal 'git@github.com:hvpaiva/hldr.git', @fake.remote_url('/srv/hldr')
  end

  def test_commit_remote_and_operation_default_to_nil
    @fake.add('/srv/unborn', status: STATUS)

    assert_nil @fake.last_commit('/srv/unborn')
    assert_nil @fake.remote_url('/srv/unborn')
    assert_nil @fake.in_progress('/srv/unborn')
  end

  def test_add_registers_the_operation_in_progress
    @fake.add('/srv/rebasing', status: STATUS, operation: 'rebase')

    assert_equal 'rebase', @fake.in_progress('/srv/rebasing')
  end

  def test_paths_are_matched_after_expansion
    @fake.add('/srv/a/../hldr', status: STATUS)

    assert_equal STATUS, @fake.status('/srv/hldr')
    assert_equal STATUS, @fake.status('/srv/hldr/')
  end

  def test_an_unknown_path_is_missing
    error = assert_raises(Slipway::Git::MissingPath) { @fake.status('/srv/nothing') }

    assert_equal '/srv/nothing: no such directory', error.message
    assert_raises(Slipway::Git::MissingPath) { @fake.last_commit('/srv/nothing') }
    assert_raises(Slipway::Git::MissingPath) { @fake.remote_url('/srv/nothing') }
  end

  def test_fail_with_a_class_raises_it_with_the_expanded_path
    @fake.fail('/srv/a/../plain', Slipway::Git::NotARepository)

    error = assert_raises(Slipway::Git::NotARepository) { @fake.status('/srv/plain') }

    assert_equal '/srv/plain: not a git repository', error.message
    assert_raises(Slipway::Git::NotARepository) { @fake.last_commit('/srv/plain') }
    assert_raises(Slipway::Git::NotARepository) { @fake.remote_url('/srv/plain') }
  end

  def test_fail_with_an_instance_raises_that_instance
    timeout = Slipway::Git::Timeout.new('/srv/slow', seconds: 0.2)
    @fake.fail('/srv/slow', timeout)

    error = assert_raises(Slipway::Git::Timeout) { @fake.status('/srv/slow') }

    assert_same timeout, error
  end

  def test_fail_accepts_every_git_error_class
    classes = [Slipway::Git::NotInstalled, Slipway::Git::Timeout, Slipway::Git::MissingPath,
               Slipway::Git::NotARepository, Slipway::Git::UnsafeRepository, Slipway::Git::Error]

    classes.each do |klass|
      @fake.fail('/srv/x', klass)

      assert_raises(klass) { @fake.status('/srv/x') }
    end
  end

  def test_add_and_fail_replace_each_other
    @fake.fail('/srv/hldr', Slipway::Git::UnsafeRepository)
    @fake.add('/srv/hldr', status: STATUS)

    assert_equal STATUS, @fake.status('/srv/hldr')

    @fake.fail('/srv/hldr', Slipway::Git::UnsafeRepository)

    assert_raises(Slipway::Git::UnsafeRepository) { @fake.status('/srv/hldr') }
  end

  def test_fetch_returns_the_canned_result_and_fetched_at_the_canned_time
    @fake.add('/srv/hldr', status: STATUS, fetch: FETCHED, fetched_at: FETCHED_AT)

    assert_same FETCHED, @fake.fetch('/srv/hldr', prune: false)
    assert_equal FETCHED_AT, @fake.fetched_at('/srv/hldr')
  end

  def test_by_default_a_fetch_brings_nothing_and_the_path_was_never_fetched
    @fake.add('/srv/hldr', status: STATUS)

    assert_empty @fake.fetch('/srv/hldr', prune: true).updates
    assert_nil @fake.fetched_at('/srv/hldr')
  end

  def test_a_canned_fetch_error_is_raised_as_fail_raises_it
    denied = Slipway::Git::ProtocolNotAllowed.new('/srv/b', protocol: 'ext', source: 'SLIPWAY_PROTOCOLS')
    @fake.add('/srv/a', status: STATUS, fetch: Slipway::Git::AuthRequired)
    @fake.add('/srv/b', status: STATUS, fetch: denied)

    error = assert_raises(Slipway::Git::AuthRequired) { @fake.fetch('/srv/x/../a', prune: false) }

    assert_equal '/srv/a: authentication required and prompts are disabled', error.message
    assert_same denied, assert_raises(Slipway::Git::ProtocolNotAllowed) { @fake.fetch('/srv/b', prune: false) }
    assert_equal STATUS, @fake.status('/srv/a')
  end

  def test_a_path_tracks_a_local_branch_when_its_fetch_raises_local_upstream
    @fake.add('/srv/a', status: STATUS, fetch: Slipway::Git::LocalUpstream)
    @fake.add('/srv/b', status: STATUS, fetch: Slipway::Git::LocalUpstream.new('/srv/b'))
    @fake.add('/srv/c', status: STATUS, fetch: Slipway::Git::AuthRequired)
    @fake.add('/srv/d', status: STATUS)

    answers = %w[/srv/x/../a /srv/b /srv/c /srv/d].map { @fake.local_upstream?(it) }

    assert_equal [true, true, false, false], answers
    assert_equal %i[local_upstream?] * 4, @fake.calls.map(&:first)
    assert_raises(Slipway::Git::MissingPath) { @fake.local_upstream?('/srv/nothing') }
  end

  def test_a_path_has_a_default_remote_from_its_upstream_its_origin_or_a_sole_remote
    @fake.add('/srv/a', status: STATUS.with(upstream: 'origin/main'))
    @fake.add('/srv/b', status: STATUS, remote: 'git@example.com:b.git')
    @fake.add('/srv/c', status: STATUS, remotes: %w[github])
    @fake.add('/srv/d', status: STATUS, remotes: %w[github gitlab])
    @fake.add('/srv/e', status: STATUS)

    answers = %w[/srv/x/../a /srv/b /srv/c /srv/d /srv/e].map { @fake.default_remote?(it) }

    assert_equal [true, true, true, false, false], answers
    assert_equal %i[default_remote?] * 5, @fake.calls.map(&:first)
    assert_raises(Slipway::Git::MissingPath) { @fake.default_remote?('/srv/nothing') }
  end

  def test_fetch_of_a_failing_or_unknown_path_raises_like_the_other_questions
    @fake.fail('/srv/plain', Slipway::Git::NotARepository)

    assert_raises(Slipway::Git::NotARepository) { @fake.fetch('/srv/plain', prune: false) }
    assert_raises(Slipway::Git::NotARepository) { @fake.fetched_at('/srv/plain') }
    assert_raises(Slipway::Git::MissingPath) { @fake.fetch('/srv/nothing', prune: false) }
    assert_raises(Slipway::Git::MissingPath) { @fake.fetched_at('/srv/nothing') }
  end

  def test_calls_lists_every_question_with_the_expanded_path_in_order
    @fake.add('/srv/hldr', status: STATUS)
    @fake.status('/srv/hldr/')
    @fake.last_commit('/srv/hldr')
    @fake.remote_url('/srv/hldr')
    @fake.fetch('/srv/a/../hldr', prune: true)
    @fake.fetched_at('/srv/hldr')
    assert_raises(Slipway::Git::MissingPath) { @fake.fetch('/srv/nothing', prune: false) }

    assert_equal [[:status, '/srv/hldr'], [:last_commit, '/srv/hldr'], [:remote_url, '/srv/hldr'],
                  [:fetch, '/srv/hldr', { prune: true }], [:fetched_at, '/srv/hldr'],
                  [:fetch, '/srv/nothing', { prune: false }]], @fake.calls
  end

  def test_calls_is_a_copy
    @fake.add('/srv/hldr', status: STATUS)
    @fake.status('/srv/hldr')
    @fake.calls.clear

    assert_equal [[:status, '/srv/hldr']], @fake.calls
  end

  def test_add_and_fail_return_the_fake_for_chaining
    assert_same @fake, @fake.add('/srv/a', status: STATUS)
    assert_same @fake, @fake.fail('/srv/b', Slipway::Git::MissingPath)
  end
end
