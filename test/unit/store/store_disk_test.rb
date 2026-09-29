# frozen_string_literal: true

require 'test_helper'
require 'slipway/store'
require 'tmpdir'

# The on-disk side of the store: layout, atomic replacement, permissions and corrupt files.
class StoreDiskTest < Minitest::Test
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

  def test_layout_is_groups_and_projects_per_group
    @store.create(Slipway::Group.new(name: 'work'))
    @store.create(Slipway::Project.new(name: 'hldr', group: 'work', path: '/p'))
    @store.create(Slipway::Project.new(name: 'site', path: '/s'))

    assert_equal %w[groups projects], Dir.children(@root).sort
    assert_equal %w[default.yaml work.yaml], Dir.children(File.join(@root, 'groups')).sort
    assert_equal %w[default work], Dir.children(File.join(@root, 'projects')).sort
    assert_equal %w[hldr.yaml], Dir.children(File.join(@root, 'projects', 'work'))
    assert_equal %w[site.yaml], Dir.children(File.join(@root, 'projects', 'default'))
  end

  def test_files_hold_the_manifest_dump
    project = @store.create(Slipway::Project.new(name: 'hldr', path: '/p', labels: { 'lang' => 'rust' }))

    assert_equal Slipway::Manifest.dump(project), File.read(File.join(@root, 'projects', 'default', 'hldr.yaml'))
    assert_equal Slipway::Manifest.dump(Slipway::Group.new(name: 'default', created_at: NOW)),
                 File.read(File.join(@root, 'groups', 'default.yaml'))
  end

  def test_root_is_private_and_files_follow_the_umask
    with_umask(0o022) { @store.create(Slipway::Project.new(name: 'hldr', path: '/p')) }

    assert_equal 0o700, File.stat(@root).mode & 0o777
    assert_equal 0o644, File.stat(File.join(@root, 'projects', 'default', 'hldr.yaml')).mode & 0o777
    assert_equal 0o644, File.stat(File.join(@root, 'groups', 'default.yaml')).mode & 0o777
  end

  def test_a_replaced_file_leaves_no_temporary_file_behind
    project = @store.create(Slipway::Project.new(name: 'hldr', path: '/p'))
    directory = File.join(@root, 'projects', 'default')
    @store.save(project.with(description: 'Changed'))

    assert_equal %w[hldr.yaml], Dir.children(directory)
    assert_includes File.read(File.join(directory, 'hldr.yaml')), "description: Changed\n"
    assert_equal 1, Dir.children(File.join(@root, 'groups')).size
  end

  def test_a_failed_write_leaves_the_previous_file_intact
    project = @store.create(Slipway::Project.new(name: 'hldr', path: '/p'))
    file = File.join(@root, 'projects', 'default', 'hldr.yaml')
    before = File.read(file)
    broken = project.with(labels: Object.new)

    assert_raises(NoMethodError) { @store.save(broken) }
    assert_equal before, File.read(file)
    assert_equal %w[hldr.yaml], Dir.children(File.dirname(file))
  end

  def test_a_corrupt_manifest_names_its_file
    file = write_file(File.join(@root, 'groups', 'work.yaml'), "kind: Group\nmetadata: [\n")
    error = assert_raises(Slipway::Manifest::Invalid) { @store.list(GROUPS) }

    assert_equal file, error.source
    assert_equal "#{file}: did not find expected node content at line 3, column 1", error.message
  end

  def test_an_invalid_manifest_names_its_file
    file = write_file(File.join(@root, 'projects', 'default', 'hldr.yaml'), "kind: Project\nmetadata:\n  name: hldr\n")
    error = assert_raises(Slipway::Manifest::Invalid) { @store.find(PROJECTS, 'hldr', group: 'default') }

    assert_equal "#{file}: \"spec.path\" is required", error.message
  end

  def test_a_manifest_stored_under_the_wrong_name_or_group_is_rejected
    file = write_file(File.join(@root, 'projects', 'default', 'hldr.yaml'),
                      "kind: Project\nmetadata:\n  name: other\nspec:\n  path: /p\n")
    error = assert_raises(Slipway::Manifest::Invalid) { @store.list(PROJECTS) }

    assert_equal "#{file}: describes project \"other\", which does not belong at this path", error.message
    write_file(File.join(@root, 'projects', 'work', 'hldr.yaml'),
               "kind: Project\nmetadata:\n  name: hldr\nspec:\n  path: /p\n")
    assert_raises(Slipway::Manifest::Invalid) { @store.find(PROJECTS, 'hldr', group: 'work') }
  end

  def test_a_manifest_of_the_wrong_kind_is_rejected
    file = write_file(File.join(@root, 'groups', 'work.yaml'),
                      "kind: Project\nmetadata:\n  name: work\nspec:\n  path: /p\n")
    error = assert_raises(Slipway::Manifest::Invalid) { @store.find(GROUPS, 'work', group: nil) }

    assert_equal "#{file}: describes project \"work\", which does not belong at this path", error.message
  end

  def test_files_written_by_hand_are_read_back
    write_file(File.join(@root, 'groups', 'work.yaml'), "kind: Group\nmetadata:\n  name: work\n")
    write_file(File.join(@root, 'projects', 'work', 'hldr.yaml'),
               "kind: Project\nmetadata:\n  name: hldr\n  group: work\nspec:\n  path: ~/p\n")

    assert_equal Slipway::Group.new(name: 'work'), @store.find(GROUPS, 'work', group: nil)
    assert_equal Slipway::Project.new(name: 'hldr', group: 'work', path: '~/p'),
                 @store.find(PROJECTS, 'hldr', group: 'work')
  end

  private

  def write_file(path, text)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, text)
    path
  end

  def with_umask(mask)
    previous = File.umask(mask)
    yield
  ensure
    File.umask(previous)
  end
end
