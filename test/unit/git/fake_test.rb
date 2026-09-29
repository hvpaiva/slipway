# frozen_string_literal: true

require 'test_helper'
require 'slipway/git'

class GitFakeTest < Minitest::Test
  STATUS = Slipway::Git::Status.new(head: 'abc1234', untracked: 1)
  COMMIT = Slipway::Git::Commit.new(sha: 'a' * 40, short: 'aaaaaaa', time: Time.at(0).utc,
                                    author: 'Fixture', email: 'fixture@example.com', subject: 'initial commit')

  def setup
    @fake = Slipway::Git::Fake.new
  end

  def test_add_registers_the_three_answers_for_a_path
    @fake.add('/srv/hldr', status: STATUS, commit: COMMIT, remote: 'git@github.com:hvpaiva/hldr.git')

    assert_equal STATUS, @fake.status('/srv/hldr')
    assert_equal COMMIT, @fake.last_commit('/srv/hldr')
    assert_equal 'git@github.com:hvpaiva/hldr.git', @fake.remote_url('/srv/hldr')
  end

  def test_commit_and_remote_default_to_nil
    @fake.add('/srv/unborn', status: STATUS)

    assert_nil @fake.last_commit('/srv/unborn')
    assert_nil @fake.remote_url('/srv/unborn')
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

  def test_add_and_fail_return_the_fake_for_chaining
    assert_same @fake, @fake.add('/srv/a', status: STATUS)
    assert_same @fake, @fake.fail('/srv/b', Slipway::Git::MissingPath)
  end
end
