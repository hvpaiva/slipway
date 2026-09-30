# frozen_string_literal: true

require 'shellwords'
require 'test_helper'

# The fields a manifest declares (remote, branch, revision, path) against the repository, and
# the repositories git cannot read.
class PlanDeclaredTest < Minitest::Test
  include PlanHelper

  URL = 'git@github.com:hvpaiva/hldr.git'
  PIN = 'b2c3d4e5f60718293a4b5c6d7e8f9012345678a1'

  def test_a_declared_remote_is_compared_with_origin
    absent = plan(remote: URL)

    assert_equal [['Remote', "no origin, manifest says #{URL}; sync never changes a remote",
                   "git -C ~/dev/hldr remote add origin #{URL}"]], lines(absent)
    assert_predicate plan(origin: URL, remote: URL), :converged?
  end

  def test_a_different_origin_is_shown_redacted_with_the_command_that_matches_the_manifest
    result = plan(origin: 'https://bot:s3cret@forge.test/hldr.git', remote: URL)

    assert_equal [['Remote', "origin is https://***@forge.test/hldr.git, manifest says #{URL}; sync never changes " \
                             'a remote', "git -C ~/dev/hldr remote set-url origin #{URL}"]], lines(result)
    assert_equal [[], [], %w[Remote]], kinds(result)
  end

  def test_a_declared_branch_is_compared_with_the_checked_out_one
    feature = plan(CLEAN.with(branch: 'feature'), branch: 'main')
    detached = plan(CommandsHelper::DETACHED, branch: 'main')

    assert_equal [['Branch', 'HEAD is on feature, manifest says main; sync never switches branches',
                   'git -C ~/dev/hldr switch main']], lines(feature)
    assert_equal %w[Branch Detached], detached.items.map(&:type)
    assert_equal 'HEAD is detached, manifest says main; sync never switches branches', detached.items.first.message
  end

  def test_a_pinned_revision_replaces_the_upstream
    held = plan(BEHIND.with(staged: 1), revision: CommandsHelper::SHA)
    moved = plan(BEHIND, revision: PIN)
    unborn = plan(CommandsHelper::UNBORN, commit: nil, revision: PIN)
    detached = plan(CommandsHelper::DETACHED, revision: PIN)

    assert_predicate held, :converged?
    assert_equal [['Revision', 'HEAD is at a1b2c3d, manifest pins b2c3d4e']], lines(moved)
    assert_equal [[], [], %w[Revision]], kinds(detached)
    assert_equal [['Revision', 'HEAD has no commits, manifest pins b2c3d4e']], lines(unborn)
  end

  def test_drift_lists_in_type_order_then_the_blocker
    result = plan(BEHIND.with(branch: 'feature', unstaged: 1),
                  origin: 'git@forge.test:o/x.git', remote: URL, branch: 'main')

    assert_equal %w[Remote Branch Behind Dirty], result.items.map(&:type)
  end

  def test_a_missing_directory_offers_the_clone_the_manifest_allows
    bare = plan(absent: true)
    cloneable = plan(absent: true, remote: URL)

    assert_equal [['Missing', 'no directory at ~/dev/hldr']], lines(bare)
    assert_equal [['Missing', 'no directory at ~/dev/hldr', "git clone -- #{URL} ~/dev/hldr"]], lines(cloneable)
    assert_equal [[], [], %w[Missing]], kinds(cloneable)
  end

  def test_a_relative_path_is_missing_for_its_own_reason_and_never_cloned
    result = plan(absent: true, path: 'dev/hldr', remote: URL)

    assert_equal [['Missing', 'relative path; register an absolute path or one starting with ~/']], lines(result)
  end

  def test_repositories_git_cannot_read_are_blocked_with_the_reason
    plain = plan(error: Slipway::Git::NotARepository)
    theirs = File.join(@home, 'their repo')
    unsafe = plan(error: Slipway::Git::UnsafeRepository, path: theirs)
    slow = plan(error: Slipway::Git::Timeout)

    assert_equal [['NotARepo', '~/dev/hldr holds files but no repository; sync clones only into an absent directory']],
                 lines(plain)
    assert_equal [['Unsafe', 'repository has dubious ownership',
                   "git config --global --add safe.directory #{Shellwords.escape(theirs)}"]], lines(unsafe)
    assert_equal [[], %w[Unknown], []], kinds(slow)
    assert_equal 'git did not finish within 10 seconds', slow.skips.first.message
  end

  def test_a_repository_git_cannot_read_is_blocked_even_when_the_project_is_held
    paused = plan(error: Slipway::Git::NotARepository, paused: true)
    fetch_only = plan(error: Slipway::Git::NotARepository, sync_policy: 'FetchOnly')

    assert_equal [[], %w[NotARepo], []], kinds(paused)
    assert_equal [[], %w[NotARepo], []], kinds(fetch_only)
  end

  def test_commands_quote_the_path_but_keep_the_tilde_a_shell_expands
    spaced = plan(CommandsHelper::DETACHED, path: '~/dev/my repo')
    home = plan(CommandsHelper::DETACHED, path: '~')
    quoted = plan(absent: true, remote: 'https://forge.test/o/r$x.git', path: "/srv/it's")

    assert_equal 'git -C ~/dev/my\\ repo status', spaced.skips.first.command
    assert_equal 'git -C ~ status', home.skips.first.command
    assert_equal "git clone -- https://forge.test/o/r\\$x.git /srv/it\\'s", quoted.items.first.command
  end
end
