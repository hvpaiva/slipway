# frozen_string_literal: true

require 'test_helper'
require 'slipway/manifest'

class ManifestTest < Minitest::Test
  SOURCE = 'hldr.yaml'
  STAMP = Time.utc(2026, 9, 29, 0, 12, 33)
  NAME_RULE = 'lowercase letters, digits and dashes, starting and ending with a letter or digit, at most 63 characters'
  KEY_RULE = 'letters, digits, dashes, underscores and dots, starting and ending with a letter or digit, ' \
             'at most 63 characters, with an optional DNS subdomain prefix and a slash'

  PROJECT_HASH = {
    'kind' => 'Project',
    'metadata' => { 'name' => 'hldr', 'group' => 'personal', 'labels' => { 'lang' => 'rust', 'tier' => 'cli' },
                    'creationTimestamp' => '2026-09-29T00:12:33Z' },
    'spec' => { 'path' => '~/dev/personal/hldr', 'description' => 'Site and CLI for hvpaiva.dev' }
  }.freeze

  PROJECT_YAML = <<~YAML
    kind: Project
    metadata:
      name: hldr
      group: personal
      labels:
        lang: rust
        tier: cli
      creationTimestamp: '2026-09-29T00:12:33Z'
    spec:
      path: "~/dev/personal/hldr"
      description: Site and CLI for hvpaiva.dev
  YAML

  PROBLEMS = {
    {} => '"kind" is required',
    { 'kind' => 'Pod' } => '"kind" must be Project or Group, not "Pod"',
    { 'kind' => 1 } => '"kind" must be a string',
    { 'kind' => 'Project', 'status' => {} } => 'unknown field "status"',
    { 'kind' => 'Project' } => '"metadata.name" is required',
    { 'kind' => 'Project', 'metadata' => 'hldr' } => '"metadata" must be a mapping',
    { 'kind' => 'Project', 'metadata' => { 'name' => 1 } } => '"metadata.name" must be a string',
    { 'kind' => 'Project', 'metadata' => { 'name' => 'Bad' } } => "\"Bad\" is not a valid project name: #{NAME_RULE}",
    { 'kind' => 'Group', 'metadata' => { 'name' => '-x' } } => "\"-x\" is not a valid group name: #{NAME_RULE}",
    { 'kind' => 'Project', 'metadata' => { 'name' => 'a', 'group' => 'Bad' } } =>
      "\"Bad\" is not a valid group name: #{NAME_RULE}",
    { 'kind' => 'Project', 'metadata' => { 'name' => 'a', 'group' => 1 } } => '"metadata.group" must be a string',
    { 'kind' => 'Group', 'metadata' => { 'name' => 'a', 'group' => 'b' } } => 'unknown field "metadata.group"',
    { 'kind' => 'Project', 'metadata' => { 'name' => 'a', 'labels' => 'x' } } => '"metadata.labels" must be a mapping',
    { 'kind' => 'Project', 'metadata' => { 'name' => 'a', 'labels' => { 'lang' => 1 } } } =>
      '"metadata.labels.lang" must be a string',
    { 'kind' => 'Project', 'metadata' => { 'name' => 'a', 'labels' => { 1 => 'x' } } } =>
      '"metadata.labels" keys must be strings',
    { 'kind' => 'Project', 'metadata' => { 'name' => 'a', 'labels' => { '-x' => 'y' } } } =>
      "\"-x\" is not a valid label key: #{KEY_RULE}",
    { 'kind' => 'Project', 'metadata' => { 'name' => 'a', 'creationTimestamp' => 1 } } =>
      '"metadata.creationTimestamp" must be an RFC 3339 timestamp',
    { 'kind' => 'Project', 'metadata' => { 'name' => 'a', 'creationTimestamp' => '2026-09-29' } } =>
      '"metadata.creationTimestamp" must be an RFC 3339 timestamp',
    { 'kind' => 'Project', 'metadata' => { 'name' => 'a', 'creationTimestamp' => '2026-09-29T00:12:33' } } =>
      '"metadata.creationTimestamp" must be an RFC 3339 timestamp',
    { 'kind' => 'Project', 'metadata' => { 'name' => 'a', 'creationTimestamp' => '2026-13-01T00:00:00Z' } } =>
      '"metadata.creationTimestamp" must be an RFC 3339 timestamp',
    { 'kind' => 'Project', 'metadata' => { 'name' => 'a', 'creationTimestamp' => STAMP } } =>
      '"metadata.creationTimestamp" must be an RFC 3339 timestamp',
    { 'kind' => 'Project', 'metadata' => { 'name' => 'a', 'labels' => {}, 'x' => 1 } } => 'unknown field "metadata.x"',
    { 'kind' => 'Project', 'metadata' => { 'name' => 'a' }, 'spec' => [] } => '"spec" must be a mapping',
    { 'kind' => 'Project', 'metadata' => { 'name' => 'a' }, 'spec' => {} } => '"spec.path" is required',
    { 'kind' => 'Project', 'metadata' => { 'name' => 'a' }, 'spec' => { 'path' => 1 } } =>
      '"spec.path" must be a string',
    { 'kind' => 'Project', 'metadata' => { 'name' => 'a' }, 'spec' => { 'path' => '/p', 'foo' => 1 } } =>
      'unknown field "spec.foo"',
    { 'kind' => 'Project', 'metadata' => { 'name' => 'a' }, 'spec' => { 'path' => '/p', 'description' => [] } } =>
      '"spec.description" must be a string',
    { 'kind' => 'Group', 'metadata' => { 'name' => 'a' }, 'spec' => { 'path' => '/p' } } => 'unknown field "spec.path"',
    { 'kind' => 'Group', 'metadata' => { 'name' => 'a' }, 'spec' => { 'description' => 1 } } =>
      '"spec.description" must be a string',
    'hldr' => 'document is not a mapping',
    nil => 'document is not a mapping'
  }.freeze

  def test_parse_reads_a_full_project
    project = Slipway::Manifest.parse(PROJECT_HASH, source: SOURCE)

    assert_equal Slipway::Project.new(name: 'hldr', group: 'personal', labels: { 'lang' => 'rust', 'tier' => 'cli' },
                                      created_at: STAMP, path: '~/dev/personal/hldr',
                                      description: 'Site and CLI for hvpaiva.dev'),
                 project
    assert_predicate project.created_at, :utc?
  end

  def test_parse_fills_the_defaults_of_a_minimal_project
    project = Slipway::Manifest.parse({ 'kind' => 'Project', 'metadata' => { 'name' => 'a' },
                                        'spec' => { 'path' => '/p' } }, source: SOURCE)

    assert_equal Slipway::Project.new(name: 'a', path: '/p'), project
  end

  def test_parse_takes_the_default_group_from_the_caller_when_metadata_has_none
    hash = { 'kind' => 'Project', 'metadata' => { 'name' => 'a' }, 'spec' => { 'path' => '/p' } }

    assert_equal 'work', Slipway::Manifest.parse(hash, source: SOURCE, default_group: 'work').group
    assert_equal 'personal', Slipway::Manifest.parse(PROJECT_HASH, source: SOURCE, default_group: 'work').group
  end

  def test_parse_reads_a_group
    group = Slipway::Manifest.parse({ 'kind' => 'Group', 'metadata' => { 'name' => 'work', 'labels' => nil },
                                      'spec' => { 'description' => 'Work' } }, source: SOURCE)

    assert_equal Slipway::Group.new(name: 'work', description: 'Work'), group
    assert_equal Slipway::Group.new(name: 'w'), Slipway::Manifest.parse({ 'kind' => 'Group',
                                                                          'metadata' => { 'name' => 'w' } },
                                                                        source: SOURCE)
  end

  def test_parse_converts_an_offset_timestamp_to_utc
    hash = { 'kind' => 'Group', 'metadata' => { 'name' => 'w', 'creationTimestamp' => '2026-09-29T02:12:33.5+02:00' } }
    created_at = Slipway::Manifest.parse(hash, source: SOURCE).created_at

    assert_equal STAMP, created_at
    assert_predicate created_at, :utc?
  end

  def test_parse_reports_the_first_problem_with_its_source
    PROBLEMS.each do |hash, problem|
      error = assert_raises(Slipway::Manifest::Invalid, hash.inspect) { Slipway::Manifest.parse(hash, source: SOURCE) }

      assert_equal "#{SOURCE}: #{problem}", error.message, hash.inspect
    end
  end

  def test_invalid_exposes_source_and_problem_and_exits_with_status_one
    error = assert_raises(Slipway::Manifest::Invalid) { Slipway::Manifest.parse({}, source: 'a.yaml:2') }

    assert_equal 'a.yaml:2', error.source
    assert_equal '"kind" is required', error.problem
    assert_equal 1, error.exit_status
    assert_kind_of Slipway::Error, error
  end

  def test_load_documents_skips_empty_documents
    text = "---\n---\nkind: Project\n--- \n# only a comment\n---\nkind: Group\n"

    assert_equal [{ 'kind' => 'Project' }, { 'kind' => 'Group' }],
                 Slipway::Manifest.load_documents(text, source: SOURCE)
    assert_empty Slipway::Manifest.load_documents('', source: SOURCE)
  end

  def test_load_documents_rejects_a_document_that_is_not_a_mapping
    error = assert_raises(Slipway::Manifest::Invalid) do
      Slipway::Manifest.load_documents("kind: Project\n---\n---\n- a\n", source: SOURCE)
    end

    assert_equal "#{SOURCE}: document 3 is not a mapping", error.message
  end

  def test_load_documents_reports_syntax_errors_with_a_position
    error = assert_raises(Slipway::Manifest::Invalid) { Slipway::Manifest.load_documents("a: [\n", source: SOURCE) }

    assert_equal "#{SOURCE}: did not find expected node content at line 2, column 1", error.message
  end

  def test_load_documents_rejects_types_outside_the_safe_set
    error = assert_raises(Slipway::Manifest::Invalid) do
      Slipway::Manifest.load_documents("creationTimestamp: 2026-09-29T00:12:33Z\n", source: SOURCE)
    end

    assert_equal "#{SOURCE}: Tried to load unspecified class: Time", error.message
    assert_raises(Slipway::Manifest::Invalid) { Slipway::Manifest.load_documents("a: &x 1\nb: *x\n", source: SOURCE) }
  end

  def test_parse_yaml_requires_exactly_one_document
    project = Slipway::Manifest.parse_yaml(PROJECT_YAML, source: SOURCE)
    none = assert_raises(Slipway::Manifest::Invalid) { Slipway::Manifest.parse_yaml("---\n", source: SOURCE) }
    two = assert_raises(Slipway::Manifest::Invalid) { Slipway::Manifest.parse_yaml("a: 1\n---\nb: 2\n", source: SOURCE) }

    assert_equal 'hldr', project.name
    assert_equal "#{SOURCE}: expected one document, found none", none.message
    assert_equal "#{SOURCE}: expected one document, found 2", two.message
  end

  def test_parse_yaml_passes_the_default_group_through
    text = "kind: Project\nmetadata:\n  name: a\nspec:\n  path: /p\n"

    assert_equal 'work', Slipway::Manifest.parse_yaml(text, source: SOURCE, default_group: 'work').group
  end

  def test_dump_writes_kubectl_style_yaml_without_a_document_marker
    project = Slipway::Manifest.parse(PROJECT_HASH, source: SOURCE)

    assert_equal PROJECT_YAML, Slipway::Manifest.dump(project)
  end

  def test_dump_of_a_bare_group
    assert_equal "kind: Group\nmetadata:\n  name: work\n  labels: {}\nspec: {}\n",
                 Slipway::Manifest.dump(Slipway::Group.new(name: 'work'))
  end

  def test_dump_does_not_fold_long_lines
    project = Slipway::Project.new(name: 'a', path: "/#{'x' * 200}")

    assert_includes Slipway::Manifest.dump(project), "path: \"/#{'x' * 200}\"\n"
  end

  def test_dump_and_parse_yaml_round_trip
    project = Slipway::Manifest.parse(PROJECT_HASH, source: SOURCE)
    group = Slipway::Group.new(name: 'work', labels: { 'a' => '' }, created_at: STAMP, description: 'Work')

    assert_equal project, Slipway::Manifest.parse_yaml(Slipway::Manifest.dump(project), source: SOURCE)
    assert_equal group, Slipway::Manifest.parse_yaml(Slipway::Manifest.dump(group), source: SOURCE)
  end
end
