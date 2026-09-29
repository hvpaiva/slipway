# frozen_string_literal: true

require 'test_helper'
require 'slipway/resources'

class ResourcesTest < Minitest::Test
  STAMP = Time.utc(2026, 9, 29, 0, 12, 33)

  def test_project_defaults
    project = Slipway::Project.new(name: 'hldr', path: '~/dev/hldr')

    assert_equal 'default', project.group
    assert_empty project.labels
    assert_nil project.created_at
    assert_nil project.description
    assert_equal 'Project', project.kind
  end

  def test_group_defaults
    group = Slipway::Group.new(name: 'work')

    assert_empty group.labels
    assert_nil group.created_at
    assert_nil group.description
    assert_equal 'Group', group.kind
  end

  def test_project_manifest_has_string_keys_in_file_order_with_sorted_labels
    project = Slipway::Project.new(name: 'hldr', group: 'personal', labels: { 'tier' => 'cli', 'lang' => 'rust' },
                                   created_at: STAMP, path: '~/dev/personal/hldr', description: 'Site and CLI')

    assert_equal({ 'kind' => 'Project',
                   'metadata' => { 'name' => 'hldr', 'group' => 'personal',
                                   'labels' => { 'lang' => 'rust', 'tier' => 'cli' },
                                   'creationTimestamp' => '2026-09-29T00:12:33Z' },
                   'spec' => { 'path' => '~/dev/personal/hldr', 'description' => 'Site and CLI' } },
                 project.to_manifest)
  end

  def test_project_manifest_omits_what_is_nil_but_keeps_empty_labels
    manifest = Slipway::Project.new(name: 'hldr', path: '/p').to_manifest

    assert_equal %w[name group labels], manifest['metadata'].keys
    assert_empty manifest['metadata']['labels']
    assert_equal({ 'path' => '/p' }, manifest['spec'])
  end

  def test_group_manifest_layout
    group = Slipway::Group.new(name: 'work', labels: { 'owner' => 'me' }, created_at: STAMP, description: 'Work')

    assert_equal({ 'kind' => 'Group',
                   'metadata' => { 'name' => 'work', 'labels' => { 'owner' => 'me' },
                                   'creationTimestamp' => '2026-09-29T00:12:33Z' },
                   'spec' => { 'description' => 'Work' } },
                 group.to_manifest)
    assert_equal({ 'kind' => 'Group', 'metadata' => { 'name' => 'work', 'labels' => {} }, 'spec' => {} },
                 Slipway::Group.new(name: 'work').to_manifest)
  end

  def test_creation_timestamp_is_written_in_utc
    local = Time.new(2026, 9, 29, 2, 0, 0, '+02:00')
    manifest = Slipway::Group.new(name: 'w', created_at: local).to_manifest

    assert_equal '2026-09-29T00:00:00Z', manifest.dig('metadata', 'creationTimestamp')
    assert_equal '+02:00', local.strftime('%:z')
  end

  def test_with_labels_replaces_the_labels_and_nothing_else
    project = Slipway::Project.new(name: 'hldr', path: '/p', labels: { 'a' => '1' })
    relabeled = project.with_labels({ 'b' => '2' })

    assert_equal({ 'b' => '2' }, relabeled.labels)
    assert_equal project.with(labels: { 'b' => '2' }), relabeled
    assert_equal({ 'a' => '1' }, project.labels)
  end

  def test_resolve_accepts_plural_singular_alias_and_kind_in_any_case
    projects = Slipway::Resources.resolve('projects')
    groups = Slipway::Resources.resolve('groups')

    %w[project proj Project PROJECTS].each { assert_equal projects, Slipway::Resources.resolve(it), it }
    %w[group Group GROUPS].each { assert_equal groups, Slipway::Resources.resolve(it), it }
  end

  def test_resolve_rejects_unknown_words
    error = assert_raises(Slipway::Error) { Slipway::Resources.resolve('pods') }

    assert_equal 'unknown resource type "pods" (known types: projects, groups)', error.message
    assert_equal 1, error.exit_status
  end

  def test_kind_describes_itself
    projects = Slipway::Resources.resolve('projects')
    groups = Slipway::Resources.resolve('groups')

    assert_equal %w[projects project proj], projects.names
    assert_equal %w[groups group], groups.names
    assert_predicate projects, :namespaced?
    refute_predicate groups, :namespaced?
    assert_equal %w[Project Group], [projects.title, groups.title]
    assert_equal [Slipway::Project, Slipway::Group], [projects.klass, groups.klass]
  end

  def test_kinds_are_exposed_as_constants_in_plural_order
    assert_equal [Slipway::Resources::PROJECTS, Slipway::Resources::GROUPS], Slipway::Resources::KINDS
    assert_equal 'default', Slipway::Resources::DEFAULT_GROUP
  end

  def test_of_finds_the_kind_of_a_resource
    assert_equal 'projects', Slipway::Resources.of(Slipway::Project.new(name: 'a', path: '/p')).plural
    assert_equal 'groups', Slipway::Resources.of(Slipway::Group.new(name: 'a')).plural
    assert_raises(ArgumentError) { Slipway::Resources.of('project') }
  end

  def test_timestamp_of_nil_is_nil
    assert_nil Slipway::Resources.timestamp(nil)
  end
end
