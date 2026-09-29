# frozen_string_literal: true

require 'test_helper'

class FetchTest < Minitest::Test
  include CommandsHelper

  OLD = SHA
  NEW = 'e4f5a6b7c8d9e0f1a2b3c4d5e6f7a8b9c0d1e2f3'
  ZERO = '0' * 40
  MOVED = Slipway::Git::FetchResult.new(updates: [['refs/remotes/origin/main', OLD, NEW]])
  NO_UPSTREAM = CLEAN.with(upstream: nil, ahead: nil, behind: nil)
  EVERY_OUTCOME = <<~TEXT
    project/api denied (AuthRequired)
      git@github.com: Permission denied (publickey).
      Run 'git -C <home>/dev/api fetch' once in a terminal to see what git needs.
    project/big failed (Timeout)
      git did not finish within 60 seconds
    project/hldr fetched
      origin/main a1b2c3d..e4f5a6b
    project/local skipped (LocalUpstream)
      the current branch tracks a local branch, not a remote one
    project/mirror failed (ProtocolNotAllowed)
      transport 'file' not allowed
      Add file to "protocols" in /cfg/config.yaml to allow it.
    project/notes skipped (NoRemote)
      no upstream, no origin and no single remote to fetch from
    project/old skipped (Missing)
      ~/dev/old: no such directory
    project/same unchanged
  TEXT
  REFS = <<~TEXT
    project/hldr fetched
      origin/main a1b2c3d..e4f5a6b
      origin/feature e4f5a6b (new)
      origin/old deleted (was a1b2c3d)
      v1.0 e4f5a6b (new)
      refs/notes/commits a1b2c3d..e4f5a6b
      and 2 more
  TEXT

  def test_each_project_prints_its_result_and_details_in_the_order_listed
    with_runtime do |runtime, home|
      register_every_outcome(runtime, home)

      assert_equal [1, EVERY_OUTCOME.gsub('<home>', home),
                    "8 projects: 1 fetched, 1 unchanged, 3 skipped, 1 denied, 2 failed\n"], run_fetch(runtime:)
    end
  end

  def test_the_status_is_one_only_when_a_project_was_denied_or_failed
    with_runtime do |runtime|
      register(runtime, 'api', fetch: Slipway::Git::AuthRequired)
      register(runtime, 'big', fetch: Slipway::Git::Timeout)
      register(runtime, 'hldr', fetch: MOVED)
      register(runtime, 'notes', status: NO_UPSTREAM)
      register(runtime, 'same')

      assert_equal 0, run_fetch('hldr', 'notes', 'same', runtime:).first
      assert_equal 1, run_fetch('api', 'same', runtime:).first
      assert_equal 1, run_fetch('big', runtime:).first
    end
  end

  def test_an_origin_without_an_upstream_is_still_fetched
    with_runtime do |runtime, home|
      register(runtime, 'det', status: NO_UPSTREAM, remote: 'git@x:y.git', fetch: MOVED)

      assert_equal [0, "project/det fetched\n  origin/main a1b2c3d..e4f5a6b\n", ''], run_fetch(runtime:)
      assert_equal([[:fetch, "#{home}/dev/det", { prune: false }]], runtime.git.calls.select { it.first == :fetch })
    end
  end

  # Git picks the only remote when neither an upstream nor origin names one, and fetches nothing
  # when several are left to choose from.
  def test_without_an_origin_or_an_upstream_only_a_sole_remote_is_fetched
    with_runtime do |runtime|
      fork = Slipway::Git::FetchResult.new(updates: [['refs/remotes/github/main', OLD, NEW]])
      register(runtime, 'det', status: NO_UPSTREAM, remote: 'git@x:y.git')
      register(runtime, 'fork', status: NO_UPSTREAM, remotes: %w[github], fetch: fork)
      register(runtime, 'twins', status: NO_UPSTREAM, remotes: %w[github gitlab], fetch: MOVED)
      expected = "project/det unchanged\nproject/fork fetched\n  github/main a1b2c3d..e4f5a6b\n" \
                 "project/twins skipped (NoRemote)\n  no upstream, no origin and no single remote to fetch from\n"

      status, out, err = run_fetch(runtime:)
      asked = runtime.git.calls.filter_map { it[1] if it.first == :default_remote? }

      assert_equal [0, expected, "3 projects: 1 fetched, 1 unchanged, 1 skipped\n"], [status, out, err]
      assert_equal(%w[fork twins], asked.map { File.basename(it) })
    end
  end

  def test_one_project_prints_no_summary
    with_runtime do |runtime|
      register(runtime, 'hldr', fetch: MOVED)

      assert_equal [0, "project/hldr fetched\n  origin/main a1b2c3d..e4f5a6b\n", ''], run_fetch(runtime:)
    end
  end

  def test_refs_show_new_and_deleted_ones_and_stop_after_five
    updates = [['refs/remotes/origin/main', OLD, NEW], ['refs/remotes/origin/feature', ZERO, NEW],
               ['refs/remotes/origin/old', OLD, ZERO], ['refs/tags/v1.0', ZERO, NEW],
               ['refs/notes/commits', OLD, NEW], ['refs/remotes/origin/a', ZERO, NEW],
               ['refs/remotes/origin/b', ZERO, NEW]]

    with_runtime do |runtime|
      register(runtime, 'hldr', fetch: Slipway::Git::FetchResult.new(updates:))

      assert_equal [0, REFS, ''], run_fetch(runtime:)
    end
  end

  def test_a_git_that_lists_no_refs_reads_as_fetched_without_details
    with_runtime do |runtime|
      register(runtime, 'hldr', fetch: Slipway::Git::FetchResult.new(updates: nil))

      assert_equal [0, "project/hldr fetched\n", ''], run_fetch(runtime:)
    end
  end

  def test_details_are_redacted_and_made_plain
    with_runtime do |runtime, home|
      message = "git exited with status 128: fatal: unable to access 'https://bot:s3cret@example.com/x.git/': " \
                "\e[2Jgone\u202E"
      register(runtime, 'broken', fetch: Slipway::Git::Error.new("#{home}/dev/broken", message))
      odd = Slipway::Git::FetchResult.new(updates: [["refs/remotes/origin/ma\u202Ein", OLD, NEW]])
      register(runtime, 'odd', fetch: odd)
      expected = "project/broken failed (Unknown)\n  git exited with status 128: fatal: unable to access " \
                 "'https://***@example.com/x.git/': ^[[2Jgone\uFFFD\n" \
                 "project/odd fetched\n  origin/ma\uFFFDin a1b2c3d..e4f5a6b\n"

      assert_equal [1, expected], run_fetch(runtime:).first(2)
    end
  end

  def test_color_paints_each_word_with_its_role_and_mutes_details_and_the_summary
    with_runtime do |runtime|
      register(runtime, 'api', fetch: Slipway::Git::AuthRequired)
      register(runtime, 'hldr', fetch: MOVED)
      register(runtime, 'notes', status: NO_UPSTREAM)
      register(runtime, 'same')

      status, out, err = run_fetch('--color=always', runtime:)
      words = out.lines.grep(/\Aproject/).map { it[/ (\e.*)$/, 1] }

      assert_equal 1, status
      assert_equal ["\e[31mdenied\e[0m (AuthRequired)", "\e[32mfetched\e[0m", "\e[33mskipped\e[0m (NoRemote)",
                    "\e[35munchanged\e[0m"], words
      assert_includes out, "project/hldr \e[32mfetched\e[0m\n  \e[90;3morigin/main a1b2c3d..e4f5a6b\e[0m\n"
      assert_equal "\e[90;3m4 projects: 1 fetched, 1 unchanged, 1 skipped, 1 denied\e[0m\n", err
    end
  end

  def test_a_denied_project_shows_what_git_printed_made_plain_then_the_hint
    with_runtime do |runtime, home|
      refused = "fatal: Authentication failed for 'https://bot:t0ken@example.com/x/'\e]0;owned\a"
      register(runtime, 'api', fetch: Slipway::Git::AuthRequired.new("#{home}/dev/api", refused))
      expected = <<~TEXT
        project/api denied (AuthRequired)
          fatal: Authentication failed for 'https://***@example.com/x/'^[]0;owned^G
          Run 'git -C #{home}/dev/api fetch' once in a terminal to see what git needs.
      TEXT

      assert_equal [1, expected, ''], run_fetch(runtime:)
    end
  end

  private

  def run_fetch(*, runtime:) = run_commands('fetch', *, runtime:, commands: [Slipway::Commands::Fetch])

  def register_every_outcome(runtime, home)
    register(runtime, 'api',
             fetch: Slipway::Git::AuthRequired.new("#{home}/dev/api", 'git@github.com: Permission denied (publickey).'))
    register(runtime, 'big', fetch: Slipway::Git::Timeout.new("#{home}/dev/big", seconds: 60))
    register(runtime, 'hldr', fetch: MOVED)
    register(runtime, 'local', fetch: Slipway::Git::LocalUpstream)
    refused = Slipway::Git::ProtocolNotAllowed.new(
      "#{home}/dev/mirror", protocol: 'file', source: '"protocols" in /cfg/config.yaml'
    )
    register(runtime, 'mirror', fetch: refused)
    register(runtime, 'notes', status: NO_UPSTREAM)
    register(runtime, 'old', status: nil)
    register(runtime, 'same')
  end
end
