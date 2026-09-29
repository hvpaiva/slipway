# frozen_string_literal: true

require 'test_helper'
require 'slipway/store'
require 'tmpdir'

class StoreTest < Minitest::Test
  PROJECTS = Slipway::Resources.resolve('projects')
  GROUPS = Slipway::Resources.resolve('groups')
  NOW = Time.utc(2026, 9, 29, 0, 12, 33)

  def setup
    @dir = Dir.mktmpdir('slipway-store-')
    @root = File.join(@dir, 'data')
    @store = Slipway::Store.new(root: @root, clock: -> { NOW })
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def test_create_stamps_the_project_and_brings_the_default_group_into_being
    created = @store.create(project('hldr'))

    assert_equal NOW, created.created_at
    assert_equal created, @store.find(PROJECTS, 'hldr', group: 'default')
    assert_equal [Slipway::Group.new(name: 'default', created_at: NOW)], @store.list(GROUPS)
  end

  def test_create_keeps_a_given_created_at
    earlier = Time.utc(2020, 1, 1)

    assert_equal earlier, @store.create(project('hldr', created_at: earlier)).created_at
  end

  def test_create_floors_the_clock_to_whole_seconds
    store = Slipway::Store.new(root: @root, clock: -> { Time.at(1_700_000_000.9).utc })

    assert_equal Time.at(1_700_000_000).utc, store.create(Slipway::Group.new(name: 'w')).created_at
  end

  def test_create_project_requires_its_group_to_exist
    error = assert_raises(Slipway::Store::NotFound) { @store.create(project('hldr', group: 'work')) }

    assert_equal 'group "work" not found', error.message
    assert_equal 1, error.exit_status
    refute_path_exists @root
  end

  def test_create_refuses_to_replace_a_resource
    @store.create(project('hldr'))
    @store.create(Slipway::Group.new(name: 'work'))
    project_error = assert_raises(Slipway::Store::Conflict) { @store.create(project('hldr', path: '/other')) }
    group_error = assert_raises(Slipway::Store::Conflict) { @store.create(Slipway::Group.new(name: 'work')) }

    assert_equal 'project "hldr" already exists', project_error.message
    assert_equal 'group "work" already exists', group_error.message
    assert_equal '/p/hldr', @store.find(PROJECTS, 'hldr', group: 'default').path
  end

  def test_write_names_are_validated_before_anything_touches_the_disk
    error = assert_raises(Slipway::Error) { @store.create(project('../escape')) }
    group_error = assert_raises(Slipway::Error) { @store.create(project('ok', group: 'Bad Group')) }

    assert_equal "\"../escape\" is not a valid project name: #{Slipway::Names::RULE}", error.message
    assert_equal "\"Bad Group\" is not a valid group name: #{Slipway::Names::RULE}", group_error.message
    refute_path_exists @root
  end

  def test_read_names_are_validated_before_any_path_is_built
    @store.create(project('hldr'))

    assert_raises(Slipway::Error) { @store.find(PROJECTS, '../hldr', group: 'default') }
    assert_raises(Slipway::Error) { @store.exist?(PROJECTS, 'hldr', group: '../default') }
    assert_raises(Slipway::Error) { @store.list(PROJECTS, group: '../default') }
    assert_raises(Slipway::Error) { @store.delete(GROUPS, '../default', group: nil) }
    assert_raises(Slipway::Error) { @store.project_count('..') }
  end

  def test_save_replaces_the_resource_as_given
    created = @store.create(project('hldr'))
    changed = created.with(description: 'Changed', labels: { 'lang' => 'rust' })

    assert_equal changed, @store.save(changed)
    assert_equal changed, @store.find(PROJECTS, 'hldr', group: 'default')
    assert_nil @store.save(project('other')).created_at
  end

  def test_save_project_creates_the_default_group_and_requires_any_other
    @store.save(project('hldr'))
    error = assert_raises(Slipway::Store::NotFound) { @store.save(project('x', group: 'work')) }

    assert @store.exist?(GROUPS, 'default', group: nil)
    assert_equal 'group "work" not found', error.message
  end

  def test_list_sorts_projects_by_group_then_name
    %w[alpha work].each { @store.create(Slipway::Group.new(name: it)) }
    %w[zeta foo-bar foo].each { @store.create(project(it, group: 'work')) }
    @store.create(project('beta', group: 'alpha'))
    @store.create(project('omega'))

    listed = @store.list(PROJECTS).map { [it.group, it.name] }

    assert_equal [%w[alpha beta], %w[default omega], %w[work foo], %w[work foo-bar], %w[work zeta]], listed
    assert_equal %w[foo foo-bar zeta], @store.list(PROJECTS, group: 'work').map(&:name)
    assert_equal %w[alpha default work], @store.list(GROUPS).map(&:name)
  end

  def test_list_of_an_empty_or_missing_store_is_empty
    assert_empty @store.list(PROJECTS)
    assert_empty @store.list(GROUPS)
    assert_empty @store.list(PROJECTS, group: 'work')
    refute_path_exists @root
  end

  def test_names_are_unique_and_sorted_across_groups
    @store.create(Slipway::Group.new(name: 'work'))
    @store.create(project('zeta'))
    @store.create(project('alpha'))
    @store.create(project('alpha', group: 'work'))

    assert_equal %w[alpha zeta], @store.names(PROJECTS)
    assert_equal %w[alpha], @store.names(PROJECTS, group: 'work')
    assert_equal %w[default work], @store.names(GROUPS)
  end

  def test_exist_and_find_look_in_the_given_group
    @store.create(Slipway::Group.new(name: 'work'))
    @store.create(project('hldr', group: 'work'))

    assert @store.exist?(PROJECTS, 'hldr', group: 'work')
    refute @store.exist?(PROJECTS, 'hldr', group: 'default')
    assert @store.exist?(GROUPS, 'work', group: 'ignored')
    assert_equal 'work', @store.find(PROJECTS, 'hldr', group: 'work').group
    assert_equal 'work', @store.find(GROUPS, 'work', group: nil).name
  end

  def test_find_reports_missing_resources_with_the_plural_kind
    project_error = assert_raises(Slipway::Store::NotFound) { @store.find(PROJECTS, 'x', group: 'default') }
    group_error = assert_raises(Slipway::Store::NotFound) { @store.find(GROUPS, 'x', group: nil) }

    assert_equal 'projects "x" not found', project_error.message
    assert_equal 'groups "x" not found', group_error.message
  end

  def test_delete_removes_one_project
    @store.create(project('hldr'))
    @store.create(project('other'))
    @store.delete(PROJECTS, 'hldr', group: 'default')

    assert_equal %w[other], @store.names(PROJECTS)
    error = assert_raises(Slipway::Store::NotFound) { @store.delete(PROJECTS, 'hldr', group: 'default') }
    assert_equal 'projects "hldr" not found', error.message
  end

  def test_delete_group_cascades_to_its_projects
    @store.create(Slipway::Group.new(name: 'work'))
    @store.create(project('a', group: 'work'))
    @store.create(project('b', group: 'work'))
    @store.create(project('c'))
    @store.delete(GROUPS, 'work', group: nil)

    refute @store.exist?(GROUPS, 'work', group: nil)
    refute_path_exists File.join(@root, 'projects', 'work')
    assert_equal %w[c], @store.names(PROJECTS)
    assert_equal 0, @store.project_count('work')
  end

  def test_delete_refuses_the_default_group_even_before_it_exists
    error = assert_raises(Slipway::Error) { @store.delete(GROUPS, 'default', group: nil) }

    assert_equal 'the default group cannot be deleted', error.message
    @store.default_group!
    assert_raises(Slipway::Error) { @store.delete(GROUPS, 'default', group: nil) }
    assert @store.exist?(GROUPS, 'default', group: nil)
  end

  def test_delete_of_a_missing_group_is_not_found
    error = assert_raises(Slipway::Store::NotFound) { @store.delete(GROUPS, 'work', group: nil) }

    assert_equal 'groups "work" not found', error.message
  end

  def test_project_count_counts_one_group
    @store.create(Slipway::Group.new(name: 'work'))
    @store.create(project('a', group: 'work'))
    @store.create(project('b', group: 'work'))
    @store.create(project('c'))

    assert_equal 2, @store.project_count('work')
    assert_equal 1, @store.project_count('default')
    assert_equal 0, @store.project_count('none')
  end

  def test_default_group_is_created_once
    first = @store.default_group!
    second = Slipway::Store.new(root: @root, clock: -> { NOW + 60 }).default_group!

    assert_equal Slipway::Group.new(name: 'default', created_at: NOW), first
    assert_equal first, second
  end

  def test_ensure_group_returns_the_name_or_raises
    @store.create(Slipway::Group.new(name: 'work'))
    error = assert_raises(Slipway::Store::NotFound) { @store.ensure_group!('other') }

    assert_equal 'work', @store.ensure_group!('work')
    assert_equal 'default', @store.ensure_group!('default')
    assert @store.exist?(GROUPS, 'default', group: nil)
    assert_equal 'group "other" not found', error.message
    assert_raises(Slipway::Error) { @store.ensure_group!('Bad') }
  end

  private

  def project(name, group: 'default', path: "/p/#{name}", created_at: nil)
    Slipway::Project.new(name:, group:, path:, created_at:)
  end
end
