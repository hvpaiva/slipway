# frozen_string_literal: true

require 'json'
require 'tempfile'

# Every write is preceded by a read, so a second run changes nothing and reports what it found.
class GitHub
  REPOSITORY = 'hvpaiva/slipway'
  ENVIRONMENT = 'release'
  TAG_POLICY = 'v*'
  # Must match the job names in .github/workflows/ci.yml.
  REQUIRED_CHECKS = ['lint', 'commits', 'test (ubuntu-latest, 3.4)', 'test (ubuntu-latest, 4.0)',
                     'test (macos-latest, 4.0)', 'coverage', 'audit', 'generated', 'package', 'completions',
                     'links'].freeze
  # The GitHub Actions app: a status of the same name posted by anything else counts for nothing.
  ACTIONS_APP_ID = 15_368
  # GitHub's built-in repository admin role.
  ADMIN_ROLE_ID = 5
  # .github/dependabot.yml applies this label to its pull requests.
  SKIP_CHANGELOG_LABEL = { name: 'skip-changelog', color: 'ededed',
                           description: 'No CHANGELOG.md line: the change is invisible to users' }.freeze
  # The merge commit takes the pull request title, which the commits job holds to Conventional Commits.
  MERGE_SETTINGS = { 'allow_merge_commit' => true, 'allow_squash_merge' => false, 'allow_rebase_merge' => false,
                     'merge_commit_title' => 'PR_TITLE', 'merge_commit_message' => 'BLANK',
                     'delete_branch_on_merge' => true }.freeze
  RUBYGEMS_PUBLISHER = [['Gem name', 'slipway'], ['Repository owner', 'hvpaiva'], ['Repository name', 'slipway'],
                        ['Workflow filename', 'release.yml'], %w[Environment release]].freeze

  class Error < StandardError; end

  # +runner+ receives an argv Array and returns [stdout, status], like CommandRunner.
  def initialize(runner:, repository: REPOSITORY, out: $stdout)
    @runner = runner
    @repository = repository
    @out = out
  end

  def setup
    ensure_merge_settings
    ensure_environment
    ensure_tag_policy
    ensure_ruleset(main_ruleset)
    ensure_ruleset(tags_ruleset)
    ensure_vulnerability_alerts
    ensure_automated_security_fixes
    ensure_skip_changelog_label
    ensure_immutable_releases
    print_publisher
  end

  def release_problems
    environment = environments[ENVIRONMENT]
    return ["the #{ENVIRONMENT} environment does not exist"] unless environment

    problems = []
    unless environment.dig('deployment_branch_policy', 'custom_branch_policies')
      problems << "the #{ENVIRONMENT} environment does not restrict deployments to custom policies"
    end
    problems << "the #{ENVIRONMENT} environment has no #{TAG_POLICY} tag policy" unless tag_policy?
    problems << 'the main ruleset does not exist' unless rulesets.key?('main')
    problems
  end

  # Only merge commits are allowed because they keep the authors' signed commits.
  def main_ruleset
    {
      name: 'main', target: 'branch', enforcement: 'active', bypass_actors: [],
      conditions: { ref_name: { include: ['refs/heads/main'], exclude: [] } },
      rules: [
        { type: 'pull_request',
          parameters: { required_approving_review_count: 0, dismiss_stale_reviews_on_push: false,
                        require_code_owner_review: false, require_last_push_approval: false,
                        required_review_thread_resolution: false, allowed_merge_methods: ['merge'] } },
        { type: 'required_status_checks',
          parameters: { strict_required_status_checks_policy: true, do_not_enforce_on_create: false,
                        required_status_checks: required_checks } },
        { type: 'required_signatures' }, { type: 'non_fast_forward' }, { type: 'deletion' }
      ]
    }
  end

  def tags_ruleset
    {
      name: 'tags', target: 'tag', enforcement: 'active',
      bypass_actors: [{ actor_id: ADMIN_ROLE_ID, actor_type: 'RepositoryRole', bypass_mode: 'always' }],
      conditions: { ref_name: { include: ["refs/tags/#{TAG_POLICY}"], exclude: [] } },
      rules: [{ type: 'creation' }, { type: 'update' }, { type: 'deletion' }]
    }
  end

  private

  def required_checks = REQUIRED_CHECKS.map { { context: it, integration_id: ACTIONS_APP_ID } }

  def ensure_merge_settings
    current = api('GET', "repos/#{@repository}").slice(*MERGE_SETTINGS.keys)
    return report('merge settings', 'already merge commits only') if current == MERGE_SETTINGS

    api('PATCH', "repos/#{@repository}", MERGE_SETTINGS)
    report('merge settings', 'updated to merge commits only')
  end

  def ensure_environment
    environment = environments[ENVIRONMENT]
    if environment&.dig('deployment_branch_policy', 'custom_branch_policies')
      return report("environment #{ENVIRONMENT}", 'already exists')
    end

    api('PUT', "repos/#{@repository}/environments/#{ENVIRONMENT}",
        { deployment_branch_policy: { protected_branches: false, custom_branch_policies: true } })
    report("environment #{ENVIRONMENT}", environment ? 'updated to custom deployment policies' : 'created')
  end

  def ensure_tag_policy
    return report("deployment policy #{TAG_POLICY} (tag)", 'already exists') if tag_policy?

    api('POST', "#{environment_path}/deployment-branch-policies", { name: TAG_POLICY, type: 'tag' })
    report("deployment policy #{TAG_POLICY} (tag)", 'created')
  end

  def ensure_ruleset(ruleset)
    existing = rulesets[ruleset[:name]]
    if existing
      api('PUT', "repos/#{@repository}/rulesets/#{existing.fetch('id')}", ruleset)
      report("ruleset #{ruleset[:name]}", 'already existed; rules updated')
    else
      api('POST', "repos/#{@repository}/rulesets", ruleset)
      report("ruleset #{ruleset[:name]}", 'created')
    end
  end

  # GitHub answers 204 when alerts are on and 404 when they are off.
  def ensure_vulnerability_alerts
    _, status = @runner.call(['gh', 'api', "repos/#{@repository}/vulnerability-alerts"])
    return report('vulnerability alerts', 'already enabled') if status.success?

    api('PUT', "repos/#{@repository}/vulnerability-alerts")
    report('vulnerability alerts', 'enabled')
  end

  def ensure_automated_security_fixes
    if api('GET', "repos/#{@repository}/automated-security-fixes")['enabled']
      return report('automated security fixes', 'already enabled')
    end

    api('PUT', "repos/#{@repository}/automated-security-fixes")
    report('automated security fixes', 'enabled')
  end

  def ensure_skip_changelog_label
    name = SKIP_CHANGELOG_LABEL[:name]
    _, status = @runner.call(['gh', 'api', "repos/#{@repository}/labels/#{name}"])
    return report("label #{name}", 'already exists') if status.success?

    api('POST', "repos/#{@repository}/labels", SKIP_CHANGELOG_LABEL)
    report("label #{name}", 'created')
  end

  # A published release can then never have its tag moved or its assets replaced, and GitHub
  # attests it; gh release create uploads to a draft first, so the Release workflow works as is.
  def ensure_immutable_releases
    if api('GET', "repos/#{@repository}/immutable-releases")['enabled']
      return report('immutable releases', 'already enabled')
    end

    api('PUT', "repos/#{@repository}/immutable-releases")
    report('immutable releases', 'enabled')
  end

  def print_publisher
    @out.puts
    @out.puts 'Last step, by hand on rubygems.org: add a GitHub Actions trusted publisher (for a gem that was'
    @out.puts 'never pushed, a pending publisher under your profile) with exactly these fields:'
    RUBYGEMS_PUBLISHER.each { |field, value| @out.puts format('  %-18<field>s %<value>s', field:, value:) }
    @out.puts 'A pending publisher expires 12 hours after it is created: push the first tag within that window,'
    @out.puts 'or create it again.'
  end

  def environments
    api('GET', "repos/#{@repository}/environments").fetch('environments', []).to_h { [it['name'], it] }
  end

  def rulesets
    api('GET', "repos/#{@repository}/rulesets").to_h { [it['name'], it] }
  end

  def tag_policy?
    policies = api('GET', "#{environment_path}/deployment-branch-policies").fetch('branch_policies', [])
    policies.any? { it['name'] == TAG_POLICY && it['type'] == 'tag' }
  end

  def environment_path = "repos/#{@repository}/environments/#{ENVIRONMENT}"

  def report(subject, outcome) = @out.puts("#{subject}: #{outcome}")

  # The body travels as a JSON file so nested rules keep their types.
  def api(method, path, body = nil)
    return request(['gh', 'api', '--method', method, path]) unless body

    Tempfile.create(['gh-api-', '.json']) do |file|
      file.write(JSON.generate(body))
      file.flush
      request(['gh', 'api', '--method', method, path, '--input', file.path])
    end
  end

  def request(argv)
    out, status = @runner.call(argv)
    raise Error, "#{argv[3]} #{argv[4]}: #{message(out)}" unless status.success?

    out.strip.empty? ? {} : JSON.parse(out)
  end

  def message(out)
    parsed = JSON.parse(out)
    parsed.is_a?(Hash) ? parsed.fetch('message', out.strip) : out.strip
  rescue JSON::ParserError
    out.strip
  end
end
