# frozen_string_literal: true

require 'test_helper'
require 'slipway/git'
require 'tmpdir'

class GitReflogTest < Minitest::Test
  include GitFixtures

  A = 'a' * 40
  B = 'b' * 40

  def setup
    @root = Dir.mktmpdir('slipway-reflog-')
    @saved = replace_env(hermetic_env(@root))
    @repo = Slipway::Git::Repository.new
  end

  def teardown
    restore_env(@saved)
    FileUtils.remove_entry(@root)
  end

  def test_parses_each_move_newest_first_with_the_time_the_branch_moved
    text = "#{B}\0refs/heads/main@{1727000100}\0slipway sync: Fast-forward\0" \
           "#{A}\0refs/heads/main@{1727000000}\0clone: from /srv/x.git\0"

    entry = Slipway::Git::ReflogEntry

    assert_equal [entry.new(sha: B, time: Time.at(1_727_000_100).utc, subject: 'slipway sync: Fast-forward'),
                  entry.new(sha: A, time: Time.at(1_727_000_000).utc, subject: 'clone: from /srv/x.git')],
                 Slipway::Git::Reflog.parse(text)
  end

  def test_an_empty_log_a_selector_without_a_time_or_a_cut_record_yields_no_entry
    assert_empty Slipway::Git::Reflog.parse('')
    assert_empty Slipway::Git::Reflog.parse("#{A}\0refs/heads/main\0commit: x\0")
    assert_empty Slipway::Git::Reflog.parse("#{A}\0refs/heads/main@{1727000000}\0")
  end

  def test_a_real_branch_lists_slipway_moves_with_their_subjects
    dir = build_repo(File.join(@root, 'stale'), 'stale')
    git!(dir, 'fetch', '-q')
    old = git!(dir, 'rev-parse', 'HEAD').chomp
    @repo.fast_forward(dir)

    entries = @repo.reflog(dir, 'main')

    assert_equal ['slipway sync: Fast-forward', old], [entries.first.subject, entries.last.sha]
    assert_equal 2, entries.size
    assert_kind_of Time, entries.first.time
  end

  def test_a_branch_without_commits_or_without_a_log_has_no_entries
    unborn = build_repo(File.join(@root, 'unborn'), 'unborn')
    silent = File.join(@root, 'silent')
    git!(@root, 'init', '-q', '-b', 'main', '--', silent)
    git!(silent, 'config', 'core.logAllRefUpdates', 'false')
    commit(silent, 'a.txt', "a\n", 'first')

    assert_equal [[], []], [@repo.reflog(unborn, 'main'), @repo.reflog(silent, 'main')]
  end

  def test_commits_between_counts_what_the_second_commit_adds
    dir = build_repo(File.join(@root, 'stale'), 'stale')
    git!(dir, 'fetch', '-q')
    old, new = %w[HEAD origin/main].map { git!(dir, 'rev-parse', it).chomp }

    assert_equal [1, 0, nil], [@repo.commits_between(dir, old, new), @repo.commits_between(dir, new, old),
                               @repo.commits_between(dir, old, 'f' * 40)]
    assert_raises(ArgumentError) { @repo.commits_between(dir, old, 'HEAD') }
  end
end
