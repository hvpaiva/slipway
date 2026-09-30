# frozen_string_literal: true

require 'test_helper'

class FetchPausedTest < Minitest::Test
  include CommandsHelper

  NEW = 'e4f5a6b7c8d9e0f1a2b3c4d5e6f7a8b9c0d1e2f3'
  MOVED = Slipway::Git::FetchResult.new(updates: [['refs/remotes/origin/main', SHA, NEW]])
  EXPECTED = <<~TEXT
    project/dots paused
    project/gone paused
    project/hldr fetched
      origin/main a1b2c3d..e4f5a6b
  TEXT

  # dots would be denied and gone skipped if either were read, so the status and the words show
  # that neither was.
  def test_a_paused_project_runs_no_git_counts_in_the_summary_and_leaves_the_status_alone
    with_runtime do |runtime|
      register(runtime, 'dots', paused: true, fetch: Slipway::Git::AuthRequired)
      register(runtime, 'gone', paused: true, status: nil)
      register(runtime, 'hldr', fetch: MOVED)

      assert_equal [0, EXPECTED, "3 projects: 1 fetched, 2 paused\n"], run_fetch(runtime:)
      assert_equal(%w[hldr], runtime.git.calls.map { File.basename(it[1]) }.uniq)
    end
  end

  def test_a_paused_project_is_painted_in_its_role_and_marked_in_a_dry_run
    with_runtime do |runtime|
      register(runtime, 'dots', paused: true)

      assert_equal [0, "project/dots \e[90;3mpaused\e[0m\n", ''], run_fetch('dots', '--color=always', runtime:)
      assert_equal [0, "project/dots paused (dry run)\n", ''], run_fetch('--dry-run=client', runtime:)
      assert_empty runtime.git.calls
    end
  end

  private

  def run_fetch(*, runtime:) = run_commands('fetch', *, runtime:, commands: [Slipway::Commands::Fetch])
end
