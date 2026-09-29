# frozen_string_literal: true

require 'fileutils'
require 'tempfile'
require_relative 'cli/errors'
require_relative 'names'
require_relative 'resources'
require_relative 'manifest'

module Slipway
  # Manifests on disk, groups/<name>.yaml and projects/<group>/<name>.yaml under one root, written atomically.
  class Store
    # A resource that is not on disk.
    class NotFound < Error; end

    # A create that would replace a resource already on disk.
    class Conflict < Error; end

    DEFAULT_GROUP = 'default'

    attr_reader :root

    def initialize(root:, clock: -> { Time.now.utc })
      @root = root
      @clock = clock
    end

    # Every resource of +kind+ sorted by group then name; +group+ narrows projects to one group.
    def list(kind, group: nil)
      files = kind.namespaced? ? project_files(group) : group_files
      resources = files.map { read(kind, it) }
      kind.namespaced? ? resources.sort_by { [it.group, it.name] } : resources.sort_by(&:name)
    end

    def find(kind, name, group:)
      file = path_for(kind, name, group)
      raise NotFound, "#{kind.plural} #{name.inspect} not found" unless File.file?(file)

      read(kind, file)
    end

    def exist?(kind, name, group:) = File.file?(path_for(kind, name, group))

    # Sorted unique names, for completion.
    def names(kind, group: nil) = list(kind, group:).map(&:name).uniq.sort

    # Writes a new resource, stamping created_at from the clock when it is nil; returns what was written.
    def create(resource)
      kind = Resources.of(resource)
      target = path_of(kind, resource)
      ensure_group!(resource.group) if kind.namespaced?
      raise Conflict, "#{kind.singular} #{resource.name.inspect} already exists" if File.exist?(target)

      stamped = resource.created_at ? resource : resource.with(created_at: @clock.call.getutc.floor)
      write(target, stamped)
      stamped
    end

    # Writes the resource as given, replacing any previous version.
    def save(resource)
      kind = Resources.of(resource)
      target = path_of(kind, resource)
      ensure_group!(resource.group) if kind.namespaced?
      write(target, resource)
      resource
    end

    # Removes a resource; removing a group also removes the registrations of its projects.
    def delete(kind, name, group:)
      file = path_for(kind, name, group)
      raise Error, 'the default group cannot be deleted' if !kind.namespaced? && name == DEFAULT_GROUP
      raise NotFound, "#{kind.plural} #{name.inspect} not found" unless File.file?(file)

      File.delete(file)
      FileUtils.rm_rf(File.join(root, 'projects', name)) unless kind.namespaced?
    end

    def project_count(group_name) = project_files(group_name).size

    # Returns +name+ once that group exists; default comes into being on first use, any other has to be there.
    def ensure_group!(name)
      Names.validate!(name, what: 'group name')
      if name == DEFAULT_GROUP
        default_group!
      elsif !File.file?(group_file(name))
        raise NotFound, "group #{name.inspect} not found"
      end
      name
    end

    # The default group, created when it is missing.
    def default_group!
      file = group_file(DEFAULT_GROUP)
      return read(Resources.resolve('groups'), file) if File.file?(file)

      create(Group.new(name: DEFAULT_GROUP))
    end

    private

    def path_for(kind, name, group)
      Names.validate!(name, what: "#{kind.singular} name")
      kind.namespaced? ? project_file(group || DEFAULT_GROUP, name) : group_file(name)
    end

    def path_of(kind, resource) = path_for(kind, resource.name, kind.namespaced? ? resource.group : nil)

    def project_file(group, name)
      File.join(root, 'projects', Names.validate!(group, what: 'group name'), "#{name}.yaml")
    end

    def group_file(name) = File.join(root, 'groups', "#{name}.yaml")

    def group_files = Dir.glob(File.join(root, 'groups', '*.yaml'))

    def project_files(group)
      pattern = group ? Names.validate!(group, what: 'group name') : '*'
      Dir.glob(File.join(root, 'projects', pattern, '*.yaml'))
    end

    # A manifest is only trusted when its kind, name and group agree with where it was found.
    def read(kind, file)
      resource = Manifest.parse_yaml(File.read(file), source: file)
      return resource if resource.is_a?(kind.klass) && path_of(kind, resource) == file

      raise Manifest::Invalid.new(file, "describes #{resource.kind.downcase} #{resource.name.inspect}, " \
                                        'which does not belong at this path')
    end

    # A temporary file in the target directory renamed over the target, so a reader never sees a partial file.
    def write(target, resource)
      FileUtils.mkdir_p(root, mode: 0o700)
      directory = File.dirname(target)
      FileUtils.mkdir_p(directory)
      Tempfile.create([".#{File.basename(target)}.", '.tmp'], directory) do |tmp|
        tmp.write(Manifest.dump(resource))
        tmp.fsync
        tmp.chmod(0o666 & ~File.umask)
        File.rename(tmp.path, target)
      end
    end
  end
end
