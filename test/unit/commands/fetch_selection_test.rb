# frozen_string_literal: true

require 'test_helper'

class FetchSelectionTest < Minitest::Test
  include CommandsHelper

  HINT = "See 'slipway fetch --help' for usage.\n"
  NO_UPSTREAM = CLEAN.with(upstream: nil, ahead: nil, behind: nil)

  # Holds each fetch until +width+ of them run at once, or half a second passes, so the widest
  # moment the pool allows is the one recorded.
  class GatedGit < Slipway::Git::Fake
    attr_reader :widest

    def initialize(width)
      super()
      @width = width
      @running = 0
      @widest = 0
      @gate = Mutex.new
      @changed = ConditionVariable.new
    end

    def fetch(path, prune:)
      @gate.synchronize { enter }
      super
    ensure
      @gate.synchronize { @running -= 1 }
    end

    private

    def enter
      @running += 1
      @widest = [@widest, @running].max
      @changed.broadcast
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 0.5
      until @running >= @width || (left = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)) <= 0
        @changed.wait(@gate, left)
      end
    end
  end

  def test_names_select_projects_bare_or_as_project_slash_name_in_the_order_given
    with_runtime do |runtime|
      %w[hldr notes plain].each { register(runtime, it) }

      assert_equal [0, "project/plain unchanged\nproject/hldr unchanged\n", "2 projects: 2 unchanged\n"],
                   run_fetch('plain', 'hldr', runtime:)
      assert_equal "project/notes unchanged\nproject/hldr unchanged\n",
                   run_fetch('project/notes', 'proj/hldr', runtime:)[1]
    end
  end

  def test_a_group_is_never_a_target_and_the_two_forms_do_not_mix
    with_runtime do |runtime|
      register(runtime, 'hldr')

      assert_equal [2, '', "error: cannot fetch a group\n#{HINT}"], run_fetch('group/default', runtime:)
      assert_equal [2, '', "error: a name in TYPE/NAME form cannot be combined with a bare name\n#{HINT}"],
                   run_fetch('hldr', 'project/hldr', runtime:)
      assert_equal [2, '', "error: \"Bad_Name\" is not a valid project name: #{Slipway::Names::RULE}\n#{HINT}"],
                   run_fetch('Bad_Name', runtime:)
    end
  end

  def test_names_cannot_be_combined_with_a_selector_or_all_groups
    with_runtime do |runtime|
      register(runtime, 'hldr')

      assert_equal [2, '', "error: name cannot be provided when a selector is specified\n#{HINT}"],
                   run_fetch('hldr', '-l', 'a=b', runtime:)
      assert_equal [2, '', "error: a resource cannot be retrieved by name across all groups\n#{HINT}"],
                   run_fetch('hldr', '-A', runtime:)
    end
  end

  def test_a_missing_name_is_reported_after_the_projects_that_exist
    with_runtime do |runtime|
      register(runtime, 'hldr')

      assert_equal [1, "project/hldr unchanged\n", "error: projects \"nope\" not found\n"],
                   run_fetch('nope', 'hldr', runtime:)
    end
  end

  def test_the_group_the_selector_and_all_groups_choose_the_projects
    with_runtime do |runtime|
      register_group(runtime, 'work')
      register(runtime, 'hldr', labels: { 'lang' => 'rust' })
      register(runtime, 'notes')
      register(runtime, 'api', group: 'work', labels: { 'lang' => 'rust' })

      assert_equal "project/api unchanged\n", run_fetch('-n', 'work', runtime:)[1]
      assert_equal "project/hldr unchanged\n", run_fetch('-l', 'lang=rust', runtime:)[1]
      assert_equal "project/hldr unchanged\nproject/api unchanged\n", run_fetch('-A', '-l', 'lang=rust', runtime:)[1]
      assert_equal [0, '', "No resources found in work group.\n"], run_fetch('-n', 'work', '-l', 'x', runtime:)
    end
  end

  def test_a_dry_run_reports_what_would_be_fetched_without_fetching
    with_runtime do |runtime|
      register(runtime, 'fork', status: NO_UPSTREAM, remotes: %w[github])
      register(runtime, 'hldr', fetch: Slipway::Git::AuthRequired)
      register(runtime, 'local', fetch: Slipway::Git::LocalUpstream)
      register(runtime, 'notes', status: NO_UPSTREAM)
      expected = "project/fork fetched (dry run)\nproject/hldr fetched (dry run)\n" \
                 "project/local skipped (LocalUpstream) (dry run)\n  " \
                 "the current branch tracks a local branch, not a remote one\n" \
                 "project/notes skipped (NoRemote) (dry run)\n  " \
                 "no upstream, no origin and no single remote to fetch from\n"

      assert_equal [0, expected, "4 projects: 2 fetched, 2 skipped (dry run)\n"],
                   run_fetch('--dry-run=client', runtime:)
      assert_empty(runtime.git.calls.select { it.first == :fetch })
    end
  end

  def test_prune_reaches_git_only_when_asked
    with_runtime do |runtime, home|
      register(runtime, 'hldr')
      run_fetch('hldr', runtime:)
      run_fetch('hldr', '--prune', runtime:)

      fetches = runtime.git.calls.select { it.first == :fetch }

      assert_equal [[:fetch, "#{home}/dev/hldr", { prune: false }], [:fetch, "#{home}/dev/hldr", { prune: true }]],
                   fetches
    end
  end

  def test_the_parallel_setting_caps_how_many_projects_fetch_at_once
    with_sandbox do |env|
      runtime = sandbox_runtime(env.merge('SLIPWAY_PARALLEL' => '2'), git: GatedGit.new(3))
      names = %w[a b c d]
      names.each { register(runtime, it) }

      status, out, = run_fetch(runtime:)

      assert_equal [0, names.map { "project/#{it} unchanged\n" }.join], [status, out]
      assert_equal 2, runtime.git.widest
    end
  end

  def test_names_complete_from_every_group_without_a_type_word
    with_runtime do |runtime|
      register_group(runtime, 'work')
      register(runtime, 'hldr')
      register(runtime, 'api', group: 'work')
      positional = Slipway::Commands::Fetch.command(->(_context, _opts) { runtime }).positionals.first

      assert_equal %w[api hldr], positional.candidates([])
    end
  end

  def test_help_shows_the_usage_and_the_options
    with_runtime do |runtime|
      status, out, = run_fetch('--help', runtime:)

      assert_equal 0, status
      assert_includes out, "Usage:\n  slipway fetch [NAME... | project/NAME...] [flags]\n"
      assert_includes out, '      --prune              Before fetching, remove any remote-tracking references'
    end
  end

  private

  def run_fetch(*, runtime:) = run_commands('fetch', *, runtime:, commands: [Slipway::Commands::Fetch])
end
