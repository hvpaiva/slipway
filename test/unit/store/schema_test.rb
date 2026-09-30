# frozen_string_literal: true

require 'test_helper'
require 'slipway/schema'

class SchemaTest < Minitest::Test
  SCHEMA = Slipway::Schema
  SOURCE = 'hldr.yaml'
  SHA = 'a1b2c3d4e5f60718293a4b5c6d7e8f9012345678'
  STAMP = Time.utc(2026, 9, 29, 0, 12, 33)

  FULL_PROJECT = Slipway::Project.new(
    name: 'hldr', group: 'personal', labels: { 'lang' => 'rust' }, created_at: STAMP, path: '~/dev/hldr',
    description: 'Site and CLI', remote: 'git@github.com:hvpaiva/hldr.git', branch: 'main', revision: SHA,
    sync_policy: Slipway::SyncPolicy::FETCH_ONLY, paused: true
  )
  FULL_GROUP = Slipway::Group.new(name: 'personal', labels: { 'lang' => 'rust' }, created_at: STAMP,
                                  description: 'Personal projects')

  def test_a_manifest_with_every_field_holds_exactly_the_fields_of_its_kind
    [FULL_PROJECT, FULL_GROUP].each do |resource|
      manifest = resource.to_manifest

      assert_equal names(SCHEMA::KINDS.fetch(resource.kind)), names_in(manifest), resource.kind
      assert_equal resource, Slipway::Manifest.parse(manifest, source: SOURCE)
    end
  end

  def test_every_resource_type_has_a_schema_whose_kind_field_names_it
    assert_equal Slipway::Resources::KINDS.map(&:title), SCHEMA::KINDS.keys
    SCHEMA::KINDS.each { |name, schema| assert_equal [name], schema.field('kind').enum }
  end

  def test_an_object_is_required_when_a_field_under_it_is
    project = SCHEMA::PROJECT
    group = SCHEMA::GROUP

    assert_equal([true, true, true], %w[kind metadata spec].map { project.field(it).required })
    assert_equal([true, false], %w[metadata spec].map { group.field(it).required })
    assert_equal %w[kind metadata.name spec.path], required_leaves(project)
    assert_equal %w[kind metadata.name], required_leaves(group)
  end

  def test_a_required_field_left_out_is_refused_in_the_words_the_reader_uses_for_it
    %w[metadata.name spec.path].each do |path|
      section, key = path.split('.')
      manifest = FULL_PROJECT.to_manifest
      manifest[section] = manifest[section].except(key)

      assert_equal "#{SOURCE}: \"#{path}\" is required", refusal(manifest)
    end
  end

  def test_the_reader_refuses_a_value_with_the_rule_of_its_field
    { %w[spec path] => ' ', %w[spec revision] => SHA[0, 7], %w[metadata creationTimestamp] => '2026-09-29',
      %w[spec syncPolicy] => 'Always' }.each do |(section, key), value|
      manifest = FULL_PROJECT.to_manifest
      manifest[section] = manifest[section].merge(key => value)

      assert_match(/\A#{SOURCE}: "#{section}\.#{key}" #{Regexp.escape(SCHEMA::PROJECT.dig(section, key).rule)}/,
                   refusal(manifest))
    end
  end

  def test_the_rules_of_fields_checked_elsewhere_quote_those_checks
    project = SCHEMA::PROJECT

    assert_equal "must be #{Slipway::Names::RULE}", project.dig('metadata', 'name').rule
    assert_equal "must be #{Slipway::Names::RULE}", project.dig('metadata', 'group').rule
    assert_equal "must be #{Slipway::Git::Url::RULE}", project.dig('spec', 'remote').rule
    assert_equal "must be #{Slipway::Git::BranchName::RULE}", project.dig('spec', 'branch').rule
    assert_equal "keys must be #{Slipway::Labels::KEY_RULE}; values must be #{Slipway::Labels::VALUE_RULE}",
                 project.dig('metadata', 'labels').rule
  end

  def test_an_absent_field_reads_as_its_default
    project = Slipway::Manifest.parse({ 'kind' => 'Project', 'metadata' => { 'name' => 'a' },
                                        'spec' => { 'path' => '/a' } }, source: SOURCE)
    spec = SCHEMA::PROJECT.field('spec')

    assert_equal [spec.field('syncPolicy').default, spec.field('paused').default],
                 [project.sync_policy, project.paused]
    assert_equal %w[FastForward false], [project.sync_policy, project.paused].map(&:to_s)
  end

  def test_an_enum_makes_the_rule
    field = SCHEMA::Field.new(name: 'x', type: SCHEMA::STRING, description: 'X.', enum: %w[A B])

    assert_equal 'must be A or B', field.rule
    assert_equal 'X. Must be A or B.', field.meaning
    assert_equal 'X.', SCHEMA::Field.new(name: 'x', type: SCHEMA::STRING, description: 'X.').meaning
  end

  def test_dig_follows_names_and_answers_nil_off_the_tree
    assert_equal 'syncPolicy', SCHEMA::PROJECT.dig('spec', 'syncPolicy').name
    assert_same SCHEMA::PROJECT, SCHEMA::PROJECT.dig
    assert_nil SCHEMA::PROJECT.dig('spec', 'nope', 'deeper')
    assert_nil SCHEMA::GROUP.dig('spec', 'path')
  end

  private

  # Arrays, not Hashes, so that the order of the fields is compared too.
  def names(field) = field.fields.map { [it.name, names(it)] }

  def names_in(hash) = hash.map { |key, value| [key, key == 'labels' || !value.is_a?(Hash) ? [] : names_in(value)] }

  def required_leaves(field, prefix = nil)
    field.fields.flat_map do |child|
      path = [prefix, child.name].compact.join('.')
      child.fields.empty? ? [(path if child.required)].compact : required_leaves(child, path)
    end
  end

  def refusal(manifest)
    assert_raises(Slipway::Manifest::Invalid) { Slipway::Manifest.parse(manifest, source: SOURCE) }.message
  end
end
