# frozen_string_literal: true

require 'fileutils'
require_relative 'error'
require_relative 'names'
require_relative 'resources'
require_relative 'manifest'

module Slipway
  class Store
    class NotFound < Error
      # kubectl's form for every kind: `projects "hldr" not found`, `groups "work" not found`.
      def self.of(kind, name) = new("#{kind.plural} #{name.inspect} not found")
    end

    class Conflict < Error; end

    DEFAULT_GROUP = Resources::DEFAULT_GROUP
    PROTECTED_GROUP = 'the default group cannot be deleted'

    attr_reader :root

    def initialize(root:, clock: -> { Time.now.utc })
      @root = root
      @clock = clock
    end

    # A file that does not hold a valid manifest raises, or is handed to the block and skipped.
    def list(kind, group: nil, &on_problem)
      files = kind.namespaced? ? project_files(group) : group_files
      resources = files.filter_map { read_or_report(kind, it, &on_problem) }
      kind.namespaced? ? resources.sort_by { [it.group, it.name] } : resources.sort_by(&:name)
    end

    # A nil `group` means the default group for projects.
    def find(kind, name, group: nil)
      file = path_for(kind, name, group)
      raise NotFound.of(kind, name) unless File.file?(file)

      read(kind, file)
    end

    # A nil `group` means the default group for projects.
    def exist?(kind, name, group: nil) = File.file?(path_for(kind, name, group))

    # Unique because project names repeat across groups; completion wants each once.
    def names(kind, group: nil) = list(kind, group:).map(&:name).uniq.sort

    def create(resource)
      kind = Resources.of(resource)
      target = path_of(kind, resource)
      ensure_group!(resource.group) if kind.namespaced?
      raise Conflict, "#{kind.singular} #{resource.name.inspect} already exists" if File.exist?(target)

      stamped = resource.created_at ? resource : resource.with(created_at: @clock.call.getutc.floor)
      write(target, stamped)
      stamped
    end

    def save(resource)
      kind = Resources.of(resource)
      target = path_of(kind, resource)
      ensure_group!(resource.group) if kind.namespaced?
      write(target, resource)
      resource
    end

    # Deleting a group also removes the registrations of its projects.
    def delete(kind, name, group: nil)
      file = path_for(kind, name, group)
      raise Error, PROTECTED_GROUP if !kind.namespaced? && name == DEFAULT_GROUP
      raise NotFound.of(kind, name) unless File.file?(file)

      File.delete(file)
      kind.namespaced? ? prune(File.dirname(file)) : FileUtils.rm_rf(File.join(root, 'projects', name))
    end

    def project_count(group_name) = project_files(group_name).size

    def group_available?(name)
      Names.validate!(name, what: 'group name')
      name == DEFAULT_GROUP || File.file?(group_file(name))
    end

    private

    def ensure_group!(name)
      raise NotFound.of(Resources::GROUPS, name) unless group_available?(name)

      create(Group.new(name: DEFAULT_GROUP)) if name == DEFAULT_GROUP && !File.file?(group_file(name))
      name
    end

    def path_for(kind, name, group)
      Names.validate!(name, what: "#{kind.singular} name")
      kind.namespaced? ? project_file(group || DEFAULT_GROUP, name) : group_file(name)
    end

    def path_of(kind, resource) = path_for(kind, resource.name, kind.namespaced? ? resource.group : nil)

    def project_file(group, name)
      File.join(root, 'projects', Names.validate!(group, what: 'group name'), "#{name}.yaml")
    end

    def group_file(name) = File.join(root, 'groups', "#{name}.yaml")

    # A group's project directory exists only while it holds a project. rmdir refuses a
    # directory that is not empty, which is the check itself; there is no locking to lose.
    def prune(directory)
      Dir.rmdir(directory)
    rescue Errno::ENOTEMPTY, Errno::ENOENT
      nil
    end

    # The root is a path the user chose, so it is the glob's base rather than part of the
    # pattern: a bracket or a star in it must not be read as a wildcard.
    def group_files = Dir.glob(File.join('groups', '*.yaml'), base: root).map { File.join(root, it) }

    def project_files(group)
      pattern = group ? Names.validate!(group, what: 'group name') : '*'
      Dir.glob(File.join('projects', pattern, '*.yaml'), base: root).map { File.join(root, it) }
    end

    def read_or_report(kind, file)
      read(kind, file)
    rescue Error => e
      raise unless block_given?

      yield e
      nil
    end

    # A manifest is only trusted when its kind, name and group agree with where it was found.
    def read(kind, file)
      resource = Manifest.parse_yaml(read_text(file), source: file)
      return resource if resource.is_a?(kind.klass) && path_of(kind, resource) == file

      raise Manifest::Invalid.new(file, "describes #{resource.kind.downcase} #{resource.name.inspect}, " \
                                        'which does not belong at this path')
    end

    def read_text(file)
      File.read(file)
    rescue SystemCallError => e
      raise Error.from_system_call(e, file)
    end

    # A temporary file in the target directory renamed over the target, so a reader never sees a partial file.
    def write(target, resource)
      require 'tempfile'
      FileUtils.mkdir_p(root, mode: 0o700)
      directory = File.dirname(target)
      FileUtils.mkdir_p(directory)
      Tempfile.create([".#{File.basename(target)}.", '.tmp'], directory) do |tmp|
        tmp.write(Manifest.dump(resource))
        tmp.fsync
        # Tempfile creates the file 0600; a manifest gets the mode File.write would give it.
        tmp.chmod(0o666 & ~File.umask)
        File.rename(tmp.path, target)
      end
    rescue SystemCallError => e
      raise Error.from_system_call(e, target)
    end
  end
end
