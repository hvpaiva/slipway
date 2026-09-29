# frozen_string_literal: true

require 'test_helper'
require 'json'
require 'stringio'
require 'tmpdir'
require_relative '../../../rakelib/support/release'

# bin/release driven end to end against a fake runner: every git and gh command is recorded
# and answered from a table, so nothing touches a repository or GitHub.
class ReleaseTest < Minitest::Test
  Status = Data.define(:success) do
    def success? = success
  end
  OK = Status.new(success: true)
  FAILED = Status.new(success: false)

  # Answers commands from +answers+ (argv joined by spaces => stdout, [stdout, status], or a
  # lambda returning either) and records [argv, stream] for each call.
  class FakeRunner
    attr_reader :calls

    def initialize(answers)
      @answers = answers
      @calls = []
    end

    def call(argv, stream: false)
      @calls << [argv, stream]
      answer = @answers.fetch(argv.join(' '), '')
      answer = answer.call if answer.respond_to?(:call)
      answer.is_a?(Array) ? answer : [answer, OK]
    end

    def commands = @calls.map { it.first.join(' ') }
  end

  # 2026-10-01 in UTC, while the local date may already be the 2nd.
  class FakeClock
    attr_reader :sleeps

    def initialize = @sleeps = []

    def now = Time.new(2026, 10, 2, 1, 30, 0, '+03:00')

    def sleep(seconds) = @sleeps << seconds
  end

  API = 'gh api --method GET repos/hvpaiva/slipway'
  URL = 'https://github.com/hvpaiva/slipway/pull/7'
  VERSION_RB = "# frozen_string_literal: true\n\nmodule Slipway\n  VERSION = '0.1.0'\nend\n"
  CHANGELOG = <<~MARKDOWN
    # Changelog

    ## [Unreleased]

    ### Added

    - `get`.

    [Unreleased]: https://github.com/hvpaiva/slipway/commits/main
  MARKDOWN

  READY = {
    'git rev-parse --abbrev-ref HEAD' => "main\n",
    'git rev-parse HEAD' => "abc123\n",
    'git rev-parse origin/main' => "abc123\n",
    "#{API}/environments" =>
      JSON.generate(environments: [{ name: 'release', deployment_branch_policy: { custom_branch_policies: true } }]),
    "#{API}/environments/release/deployment-branch-policies" =>
      JSON.generate(branch_policies: [{ id: 1, name: 'v*', type: 'tag' }]),
    "#{API}/rulesets" => JSON.generate([{ id: 9, name: 'main' }]),
    'gh pr create --base main --head release/v0.2.0 --title chore: release v0.2.0 --body ' \
    "Releases slipway 0.2.0. Its tag goes on the merge commit.\n\n### Added\n\n- `get`.\n" => "#{URL}\n",
    "gh pr view #{URL} --json statusCheckRollup --jq .statusCheckRollup | length" => "11\n",
    "gh pr view #{URL} --json mergeCommit --jq .mergeCommit.oid" => "def456\n",
    'gh run list --workflow release.yml --branch v0.2.0 --event push --limit 1 --json databaseId ' \
    '--jq .[0].databaseId // empty' => "42\n"
  }.freeze

  VALIDATION = [
    'git fetch origin --tags',
    'git rev-parse --abbrev-ref HEAD',
    'git status --porcelain',
    'git rev-parse HEAD',
    'git rev-parse origin/main',
    'git tag --list v0.2.0',
    'git ls-remote --tags origin refs/tags/v0.2.0',
    "#{API}/environments",
    "#{API}/environments/release/deployment-branch-policies",
    "#{API}/rulesets"
  ].freeze

  PREPARE = [
    'git switch -c release/v0.2.0',
    'bundle exec rake generate',
    'bundle exec rake check',
    'git add -- lib/slipway/version.rb CHANGELOG.md Gemfile.lock man test/fixtures/golden',
    'git commit -S -m chore: release v0.2.0',
    'git push -u origin release/v0.2.0',
    'gh pr create --base main --head release/v0.2.0 --title chore: release v0.2.0 --body ' \
    "Releases slipway 0.2.0. Its tag goes on the merge commit.\n\n### Added\n\n- `get`.\n"
  ].freeze

  PUBLISH = [
    "gh pr view #{URL} --json statusCheckRollup --jq .statusCheckRollup | length",
    "gh pr checks #{URL} --watch --fail-fast",
    "gh pr merge #{URL} --merge --delete-branch",
    "gh pr view #{URL} --json mergeCommit --jq .mergeCommit.oid",
    'git fetch origin --tags',
    'git switch main',
    'git merge --ff-only origin/main',
    'git tag -s v0.2.0 -m v0.2.0 def456',
    'git push origin v0.2.0',
    'gh run list --workflow release.yml --branch v0.2.0 --event push --limit 1 --json databaseId ' \
    '--jq .[0].databaseId // empty',
    'gh run watch 42 --exit-status'
  ].freeze

  RELEASED_CHANGELOG = <<~MARKDOWN
    # Changelog

    ## [Unreleased]

    ## [0.2.0] - 2026-10-01

    ### Added

    - `get`.

    [Unreleased]: https://github.com/hvpaiva/slipway/compare/v0.2.0...HEAD
    [0.2.0]: https://github.com/hvpaiva/slipway/releases/tag/v0.2.0
  MARKDOWN

  def setup
    @root = Dir.mktmpdir('slipway-release-')
    FileUtils.mkdir_p(File.join(@root, 'lib', 'slipway'))
    File.write(File.join(@root, 'lib', 'slipway', 'version.rb'), VERSION_RB)
    File.write(File.join(@root, 'CHANGELOG.md'), CHANGELOG)
    @out = StringIO.new
    @clock = FakeClock.new
  end

  def teardown
    FileUtils.rm_rf(@root)
  end

  def release(version = '0.2.0', answers = {}, **)
    @runner = FakeRunner.new(READY.merge(answers))
    Release.new(version, root: @root, runner: @runner, clock: @clock, out: @out, **).run
  end

  def refusal(version = '0.2.0', answers = {}, **)
    assert_raises(Release::Error) { release(version, answers, **) }.message
  end

  def file(name) = File.read(File.join(@root, name))

  def test_plain_mode_prepares_the_branch_and_opens_the_pull_request
    release

    assert_equal VALIDATION + PREPARE, @runner.commands
    assert_equal VERSION_RB.sub('0.1.0', '0.2.0'), file('lib/slipway/version.rb')
    assert_equal RELEASED_CHANGELOG, file('CHANGELOG.md')
    assert_includes @out.string, "Opened #{URL}\n"
    assert_includes @out.string, "  git tag -s v0.2.0 -m v0.2.0\n"
    assert_equal(['bundle exec rake generate', 'bundle exec rake check', 'git push -u origin release/v0.2.0'],
                 @runner.calls.select(&:last).map { it.first.join(' ') })
  end

  def test_push_mode_merges_tags_the_merge_commit_and_watches_the_release
    release(push: true)

    assert_equal VALIDATION + PREPARE + PUBLISH, @runner.commands
    assert_empty @clock.sleeps
    assert @out.string.end_with?("Released v0.2.0.\n")
  end

  def test_push_mode_polls_until_github_registers_the_checks
    count = "gh pr view #{URL} --json statusCheckRollup --jq .statusCheckRollup | length"
    answers = %W[0\n 0\n 11\n]
    release('0.2.0', { count => -> { answers.shift } }, push: true)

    assert_equal [Release::POLL_SECONDS] * 2, @clock.sleeps
    assert_equal 3, @runner.commands.count(count)
  end

  def test_push_mode_stops_when_a_check_fails
    message = refusal('0.2.0', { "gh pr checks #{URL} --watch --fail-fast" => ['', FAILED] }, push: true)

    assert_equal "gh pr checks #{URL} --watch --fail-fast failed; fix the failure on release/v0.2.0 and push", message
    refute_includes @runner.commands, "gh pr merge #{URL} --merge --delete-branch"
  end

  def test_dry_run_validates_and_prints_the_diff_without_writing
    release('0.2.0', {}, dry_run: true)

    diffs = @runner.calls.drop(VALIDATION.size).map { it.first.first(7) }

    assert_equal VALIDATION, @runner.commands.first(VALIDATION.size)
    assert_equal [%w[diff -u --label a/lib/slipway/version.rb --label b/lib/slipway/version.rb lib/slipway/version.rb],
                  %w[diff -u --label a/CHANGELOG.md --label b/CHANGELOG.md CHANGELOG.md]], diffs
    assert_equal VERSION_RB, file('lib/slipway/version.rb')
    assert_equal CHANGELOG, file('CHANGELOG.md')
    assert_includes @out.string, 'Dry run: v0.2.0 is ready to be cut; nothing was written, committed or pushed.'
  end

  def test_dry_run_diffs_compare_against_the_new_text
    seen = []
    runner = FakeRunner.new(READY)
    runner.define_singleton_method(:call) do |argv, stream: false|
      seen << File.read(argv.last) if argv.first == 'diff'
      super(argv, stream:)
    end
    Release.new('0.2.0', root: @root, runner:, clock: @clock, out: @out, dry_run: true).run

    assert_equal [VERSION_RB.sub('0.1.0', '0.2.0'), RELEASED_CHANGELOG], seen
  end

  def test_branch_option_releases_from_another_branch
    release('0.2.0', { 'git rev-parse --abbrev-ref HEAD' => "hotfix\n", 'git rev-parse origin/hotfix' => "abc123\n" },
            branch: 'hotfix')

    assert_includes @runner.commands, 'git rev-parse origin/hotfix'
    assert_includes @runner.commands.last, 'gh pr create --base hotfix --head release/v0.2.0'
  end

  def test_refuses_a_dirty_tree
    message = refusal('0.2.0', { 'git status --porcelain' => " M README.md\n" })

    assert_equal "the working tree has uncommitted changes; commit or stash them first:\n M README.md\n", message
    refute_includes @runner.commands, 'git switch -c release/v0.2.0'
  end

  def test_refuses_another_branch_or_one_that_differs_from_origin
    assert_equal 'releases are cut from main, but topic is checked out (--branch overrides)',
                 refusal('0.2.0', { 'git rev-parse --abbrev-ref HEAD' => "topic\n" })
    assert_equal 'main is not at origin/main; pull or push first',
                 refusal('0.2.0', { 'git rev-parse origin/main' => "f0\n" })
  end

  def test_refuses_a_lower_version
    assert_equal '0.0.9 is lower than the current version 0.1.0', refusal('0.0.9')
    assert_empty @runner.calls
  end

  def test_refuses_the_current_version_once_it_is_released
    File.write(File.join(@root, 'CHANGELOG.md'), RELEASED_CHANGELOG.gsub('0.2.0', '0.1.0'))

    assert_equal '0.1.0 is already released (CHANGELOG.md has its heading); pick a greater version', refusal('0.1.0')
  end

  def test_releases_the_version_under_development_while_it_has_no_heading
    release('0.1.0', { 'git rev-parse --abbrev-ref HEAD' => "main\n" }, dry_run: true)

    assert_includes @out.string, 'Dry run: v0.1.0 is ready to be cut'
    assert_includes @runner.commands, 'git ls-remote --tags origin refs/tags/v0.1.0'
  end

  def test_refuses_a_prerelease_or_malformed_version
    assert_equal '0.2.0.rc1 is a prerelease; releases are X.Y.Z', refusal('0.2.0.rc1')
    assert_equal '"two" is not a version number', refusal('two')
    assert_equal '1.0 is not of the form X.Y.Z', refusal('1.0')
  end

  def test_refuses_an_existing_tag
    assert_equal 'tag v0.2.0 already exists locally', refusal('0.2.0', { 'git tag --list v0.2.0' => "v0.2.0\n" })

    remote = { 'git ls-remote --tags origin refs/tags/v0.2.0' => "abc123\trefs/tags/v0.2.0\n" }

    assert_equal 'tag v0.2.0 already exists on origin', refusal('0.2.0', remote)
  end

  def test_refuses_an_empty_unreleased_section
    File.write(File.join(@root, 'CHANGELOG.md'), RELEASED_CHANGELOG)

    assert_equal 'CHANGELOG.md has nothing under "## [Unreleased]"; add the release notes first', refusal
  end

  def test_refuses_a_missing_release_environment
    message = refusal('0.2.0', { "#{API}/environments" => JSON.generate(total_count: 0, environments: []) })

    assert_equal "the repository is not ready for releases:\n  - the release environment does not exist\n" \
                 'Run bundle exec rake github:setup (safe to run again), then retry.', message
    assert_equal VALIDATION.first(8), @runner.commands
  end

  def test_refuses_when_gh_cannot_read_the_settings
    failure = [JSON.generate(message: 'Bad credentials'), FAILED]

    assert_equal 'could not read the repository settings through gh: GET repos/hvpaiva/slipway/environments: ' \
                 'Bad credentials', refusal('0.2.0', { "#{API}/environments" => failure })
  end

  def test_a_failing_check_leaves_the_edits_on_the_release_branch
    message = refusal('0.2.0', { 'bundle exec rake check' => ['', FAILED] })

    assert_equal 'bundle exec rake check failed; the edits stay on release/v0.2.0 for you to inspect', message
    assert_equal RELEASED_CHANGELOG, file('CHANGELOG.md')
    refute_includes @runner.commands, 'git commit -S -m chore: release v0.2.0'
  end
end
