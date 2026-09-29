# frozen_string_literal: true

require 'test_helper'
require 'slipway/manifest'

class ManifestSpecTest < Minitest::Test
  SOURCE = 'hldr.yaml'
  SHA1 = 'a1b2c3d4e5f60718293a4b5c6d7e8f9012345678'
  SHA256 = "#{SHA1}#{'0' * 24}".freeze
  URL_RULE = Slipway::Git::Url::RULE
  BRANCH_RULE = Slipway::Git::BranchName::RULE
  CREDENTIALS = '"spec.remote" must not embed credentials; use a credential helper'
  REVISION = '"spec.revision" must be a full object name, 40 or 64 lowercase hexadecimal characters'

  FULL_YAML = <<~YAML.freeze
    kind: Project
    metadata:
      name: hldr
      group: default
      labels: {}
    spec:
      path: "~/dev/hldr"
      remote: git@github.com:hvpaiva/hldr.git
      branch: main
      revision: #{SHA1}
      syncPolicy: FetchOnly
      paused: true
  YAML

  PROBLEMS = {
    { 'remote' => 1 } => '"spec.remote" must be a string',
    { 'remote' => 'https://u:p@h/x' } => CREDENTIALS,
    { 'remote' => 'https://ghp_token@h/x' } => CREDENTIALS,
    { 'remote' => 'ssh://u:p@h/x' } => CREDENTIALS,
    { 'remote' => 'https://ci:AbC/dEf+gh=@example.com/o/r.git' } => CREDENTIALS,
    { 'remote' => 'u:AbC/dEf@git.example.com:o/r.git' } => CREDENTIALS,
    { 'remote' => 'https://tok#en@example.com/o/r.git' } => "\"spec.remote\" is not a valid remote URL: #{URL_RULE}",
    { 'remote' => 'ext::sh -c x' } => "\"ext::sh -c x\" is not a valid remote URL: #{URL_RULE}",
    { 'remote' => 'fd::3' } => "\"fd::3\" is not a valid remote URL: #{URL_RULE}",
    { 'remote' => '-oProxyCommand=x' } => "\"-oProxyCommand=x\" is not a valid remote URL: #{URL_RULE}",
    { 'remote' => 'ssh://-oProxyCommand=x/y' } => "\"ssh://-oProxyCommand=x/y\" is not a valid remote URL: #{URL_RULE}",
    { 'branch' => ['main'] } => '"spec.branch" must be a string',
    { 'branch' => '-q' } => "\"-q\" is not a valid branch name: #{BRANCH_RULE}",
    { 'branch' => '--track' } => "\"--track\" is not a valid branch name: #{BRANCH_RULE}",
    { 'branch' => 'a..b' } => "\"a..b\" is not a valid branch name: #{BRANCH_RULE}",
    { 'branch' => 'x.lock' } => "\"x.lock\" is not a valid branch name: #{BRANCH_RULE}",
    { 'branch' => "main\u001B[8m" } => "\"main\\e[8m\" is not a valid branch name: #{BRANCH_RULE}",
    { 'branch' => "main\u202E" } => "\"main\u202E\" is not a valid branch name: #{BRANCH_RULE}",
    { 'revision' => SHA1[0, 7] } => REVISION,
    { 'revision' => SHA1.upcase } => REVISION,
    { 'revision' => "#{SHA1}0" } => REVISION,
    { 'revision' => "-#{SHA1[1..]}" } => REVISION,
    { 'revision' => 1234 } => REVISION,
    { 'syncPolicy' => 'Always' } => '"spec.syncPolicy" must be FastForward or FetchOnly, not "Always"',
    { 'syncPolicy' => 'fastforward' } => '"spec.syncPolicy" must be FastForward or FetchOnly, not "fastforward"',
    { 'syncPolicy' => true } => '"spec.syncPolicy" must be a string',
    { 'paused' => 'true' } => '"spec.paused" must be a boolean',
    { 'paused' => 1 } => '"spec.paused" must be a boolean'
  }.freeze

  def test_parse_reads_every_spec_field
    project = parse('remote' => 'git@github.com:hvpaiva/hldr.git', 'branch' => 'main', 'revision' => SHA256,
                    'syncPolicy' => 'FetchOnly', 'paused' => true)

    assert_equal ['git@github.com:hvpaiva/hldr.git', 'main', SHA256, 'FetchOnly', true],
                 [project.remote, project.branch, project.revision, project.sync_policy, project.paused]
  end

  def test_absent_fields_take_their_defaults
    project = parse

    assert_equal [nil, nil, nil, 'FastForward', false],
                 [project.remote, project.branch, project.revision, project.sync_policy, project.paused]
  end

  def test_a_field_written_at_its_default_reads_as_the_same_project
    explicit = parse('syncPolicy' => 'FastForward', 'paused' => false)

    assert_equal parse, explicit
    assert_equal Slipway::Manifest.dump(parse), Slipway::Manifest.dump(explicit)
  end

  def test_every_rule_reports_its_problem_with_the_source
    PROBLEMS.each do |spec, problem|
      error = assert_raises(Slipway::Manifest::Invalid, spec.inspect) { parse(spec) }

      assert_equal "#{SOURCE}: #{problem}", error.message, spec.inspect
    end
  end

  def test_a_group_has_none_of_the_project_fields
    %w[remote branch revision syncPolicy paused].each do |field|
      error = assert_raises(Slipway::Manifest::Invalid) do
        Slipway::Manifest.parse({ 'kind' => 'Group', 'metadata' => { 'name' => 'w' }, 'spec' => { field => 'x' } },
                                source: SOURCE)
      end

      assert_equal "#{SOURCE}: unknown field \"spec.#{field}\"", error.message
    end
  end

  def test_dump_writes_the_fields_after_the_path_and_reads_them_back
    project = Slipway::Manifest.parse_yaml(FULL_YAML, source: SOURCE)

    assert_equal FULL_YAML, Slipway::Manifest.dump(project)
    assert_equal project, Slipway::Manifest.parse_yaml(Slipway::Manifest.dump(project), source: SOURCE)
  end

  private

  def parse(spec = {})
    Slipway::Manifest.parse({ 'kind' => 'Project', 'metadata' => { 'name' => 'hldr' },
                              'spec' => { 'path' => '~/dev/hldr' }.merge(spec) }, source: SOURCE)
  end
end
