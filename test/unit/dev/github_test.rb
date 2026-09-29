# frozen_string_literal: true

require 'test_helper'
require 'json'
require 'stringio'
require 'yaml'
require_relative '../../../rakelib/support/github'

class GitHubTest < Minitest::Test
  Status = Data.define(:success) do
    def success? = success
  end

  # +answers+ maps "METHOD path" to a JSON-able object, or to :missing for a 404.
  class FakeGh
    attr_reader :requests

    def initialize(answers)
      @answers = answers
      @requests = []
    end

    def call(argv)
      method = argv.include?('--method') ? argv[argv.index('--method') + 1] : 'GET'
      path = argv.find { it.start_with?('repos/') }
      body = argv.include?('--input') ? JSON.parse(File.read(argv[argv.index('--input') + 1])) : nil
      @requests << [method, path, body]
      answer = @answers.fetch("#{method} #{path}", {})
      return [JSON.generate(message: 'Not Found'), Status.new(success: false)] if answer == :missing

      [answer.nil? ? '' : JSON.generate(answer), Status.new(success: true)]
    end

    def calls = @requests.map { it.first(2).join(' ') }

    def body(call) = @requests.find { it.first(2).join(' ') == call }&.last
  end

  REPO = 'repos/hvpaiva/slipway'
  POLICIES = "#{REPO}/environments/release/deployment-branch-policies".freeze

  NOTHING = {
    "GET #{REPO}" => { allow_merge_commit: true, allow_squash_merge: true, allow_rebase_merge: true,
                       merge_commit_title: 'MERGE_MESSAGE', merge_commit_message: 'PR_TITLE',
                       delete_branch_on_merge: false },
    "GET #{REPO}/environments" => { total_count: 0, environments: [] },
    "GET #{POLICIES}" => { total_count: 0, branch_policies: [] },
    "GET #{REPO}/rulesets" => [],
    "GET #{REPO}/vulnerability-alerts" => :missing,
    "GET #{REPO}/automated-security-fixes" => { enabled: false, paused: false },
    "GET #{REPO}/labels/skip-changelog" => :missing,
    "GET #{REPO}/immutable-releases" => { enabled: false, enforced_by_owner: false }
  }.freeze

  EVERYTHING = {
    "GET #{REPO}" => GitHub::MERGE_SETTINGS.merge('private' => false),
    "GET #{REPO}/environments" =>
      { environments: [{ name: 'release', deployment_branch_policy: { protected_branches: false,
                                                                      custom_branch_policies: true } }] },
    "GET #{POLICIES}" => { branch_policies: [{ id: 3, name: 'v*', type: 'tag' }] },
    "GET #{REPO}/rulesets" => [{ id: 11, name: 'main', target: 'branch' }, { id: 12, name: 'tags', target: 'tag' }],
    "GET #{REPO}/vulnerability-alerts" => nil,
    "GET #{REPO}/automated-security-fixes" => { enabled: true, paused: false },
    "GET #{REPO}/labels/skip-changelog" => { name: 'skip-changelog' },
    "GET #{REPO}/immutable-releases" => { enabled: true, enforced_by_owner: false }
  }.freeze

  def setup_with(answers)
    @gh = FakeGh.new(answers)
    @out = StringIO.new
    GitHub.new(runner: @gh, out: @out).setup
  end

  def test_setup_on_a_bare_repository_creates_everything
    setup_with(NOTHING)

    assert_equal ["GET #{REPO}", "PATCH #{REPO}", "GET #{REPO}/environments", "PUT #{REPO}/environments/release",
                  "GET #{POLICIES}", "POST #{POLICIES}", "GET #{REPO}/rulesets", "POST #{REPO}/rulesets",
                  "GET #{REPO}/rulesets", "POST #{REPO}/rulesets", "GET #{REPO}/vulnerability-alerts",
                  "PUT #{REPO}/vulnerability-alerts", "GET #{REPO}/automated-security-fixes",
                  "PUT #{REPO}/automated-security-fixes", "GET #{REPO}/labels/skip-changelog",
                  "POST #{REPO}/labels", "GET #{REPO}/immutable-releases", "PUT #{REPO}/immutable-releases"],
                 @gh.calls
    assert_equal ['merge settings: updated to merge commits only', 'environment release: created',
                  'deployment policy v* (tag): created', 'ruleset main: created', 'ruleset tags: created',
                  'vulnerability alerts: enabled', 'automated security fixes: enabled',
                  'label skip-changelog: created', 'immutable releases: enabled'],
                 @out.string.lines(chomp: true).first(9)
  end

  def test_setup_sends_the_environment_and_policy_bodies
    setup_with(NOTHING)

    assert_equal({ 'allow_merge_commit' => true, 'allow_squash_merge' => false, 'allow_rebase_merge' => false,
                   'merge_commit_title' => 'PR_TITLE', 'merge_commit_message' => 'BLANK',
                   'delete_branch_on_merge' => true },
                 @gh.body("PATCH #{REPO}"))
    assert_equal({ 'deployment_branch_policy' => { 'protected_branches' => false, 'custom_branch_policies' => true } },
                 @gh.body("PUT #{REPO}/environments/release"))
    assert_equal({ 'name' => 'v*', 'type' => 'tag' }, @gh.body("POST #{POLICIES}"))
    assert_equal 'skip-changelog', @gh.body("POST #{REPO}/labels")['name']
  end

  def posted_ruleset(name)
    setup_with(NOTHING)
    @gh.requests.find { it.first == 'POST' && it[2]&.fetch('name', nil) == name }.last
  end

  def test_the_main_ruleset_requires_a_pull_request_signatures_and_no_rewrites
    main = posted_ruleset('main')
    rules = main.fetch('rules').to_h { [it['type'], it['parameters']] }
    review = rules['pull_request'].values_at('required_approving_review_count', 'dismiss_stale_reviews_on_push',
                                             'allowed_merge_methods')

    assert_equal %w[pull_request required_status_checks required_signatures non_fast_forward deletion], rules.keys
    assert_equal [0, false, ['merge']], review
    assert_equal({ 'include' => ['refs/heads/main'], 'exclude' => [] }, main.dig('conditions', 'ref_name'))
    assert_empty main['bypass_actors']
  end

  def test_the_main_ruleset_requires_every_ci_job_on_an_up_to_date_branch
    checks = posted_ruleset('main').fetch('rules').find { it['type'] == 'required_status_checks' }['parameters']
    contexts = checks['required_status_checks'].map { it['context'] }

    assert checks['strict_required_status_checks_policy']
    assert_equal GitHub::REQUIRED_CHECKS, contexts
    assert_equal [GitHub::ACTIONS_APP_ID], checks['required_status_checks'].map { it['integration_id'] }.uniq
  end

  # The required contexts are the names GitHub gives the CI jobs, matrix legs included, so a
  # renamed or added job cannot leave the ruleset waiting for a check that never reports.
  def test_the_required_checks_are_the_ci_job_names
    jobs = YAML.safe_load_file(File.expand_path('../../../.github/workflows/ci.yml', __dir__)).fetch('jobs')
    names = jobs.flat_map do |id, job|
      matrix = job.dig('strategy', 'matrix')
      next [id] unless matrix

      legs = matrix['os'].product(matrix['ruby']) + matrix.fetch('include', []).map { it.values_at('os', 'ruby') }
      legs.map { |os, ruby| "#{id} (#{os}, #{ruby})" }
    end

    assert_equal names, GitHub::REQUIRED_CHECKS
    assert_equal ['lint', 'commits', 'test (ubuntu-latest, 3.4)', 'test (ubuntu-latest, 4.0)',
                  'test (macos-latest, 4.0)', 'coverage', 'audit', 'generated', 'package', 'completions', 'links'],
                 names
  end

  def test_the_tags_ruleset_leaves_v_tags_to_the_admin_role
    tags = posted_ruleset('tags')

    assert_equal(%w[creation update deletion], tags['rules'].map { it['type'] })
    assert_equal ['refs/tags/v*'], tags.dig('conditions', 'ref_name', 'include')
    assert_equal [{ 'actor_id' => 5, 'actor_type' => 'RepositoryRole', 'bypass_mode' => 'always' }],
                 tags['bypass_actors']
  end

  def test_setup_run_again_only_refreshes_the_rulesets
    setup_with(EVERYTHING)

    writes = @gh.calls.reject { it.start_with?('GET ') }

    assert_equal ["PUT #{REPO}/rulesets/11", "PUT #{REPO}/rulesets/12"], writes
    assert_equal ['merge settings: already merge commits only', 'environment release: already exists',
                  'deployment policy v* (tag): already exists', 'ruleset main: already existed; rules updated',
                  'ruleset tags: already existed; rules updated', 'vulnerability alerts: already enabled',
                  'automated security fixes: already enabled', 'label skip-changelog: already exists',
                  'immutable releases: already enabled'],
                 @out.string.lines(chomp: true).first(9)
  end

  def test_setup_ends_with_the_rubygems_publisher_table
    setup_with(EVERYTHING)

    assert_includes @out.string, "  Workflow filename  release.yml\n"
    assert_includes @out.string, "  Environment        release\n"
    assert_includes @out.string, 'expires 12 hours after it is created'
  end

  def test_an_environment_open_to_every_branch_is_restricted
    answers = EVERYTHING.merge("GET #{REPO}/environments" => { environments: [{ name: 'release' }] })
    setup_with(answers)

    assert_includes @gh.calls, "PUT #{REPO}/environments/release"
    assert_includes @out.string, "environment release: updated to custom deployment policies\n"
  end

  def test_a_failed_write_raises_with_github_message
    gh = FakeGh.new(NOTHING.merge("PATCH #{REPO}" => :missing))

    error = assert_raises(GitHub::Error) { GitHub.new(runner: gh, out: StringIO.new).setup }

    assert_equal "PATCH #{REPO}: Not Found", error.message
  end

  def test_release_problems_are_empty_when_everything_exists
    assert_empty GitHub.new(runner: FakeGh.new(EVERYTHING)).release_problems
  end

  def test_release_problems_name_what_is_missing
    assert_equal ['the release environment does not exist'], GitHub.new(runner: FakeGh.new(NOTHING)).release_problems

    open_environment = NOTHING.merge("GET #{REPO}/environments" => { environments: [{ name: 'release' }] })

    assert_equal ['the release environment does not restrict deployments to custom policies',
                  'the release environment has no v* tag policy', 'the main ruleset does not exist'],
                 GitHub.new(runner: FakeGh.new(open_environment)).release_problems
  end

  def test_release_problems_never_write
    gh = FakeGh.new(NOTHING)
    GitHub.new(runner: gh).release_problems

    assert(gh.calls.all? { it.start_with?('GET ') })
  end
end
