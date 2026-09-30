# frozen_string_literal: true

require_relative 'error'

module Slipway
  # Finds the git repositories at and under a directory.
  class Scanner
    # `problems` holds a Problem for each directory that could not be read.
    Result = Data.define(:repositories, :problems)
    # `detail` is the system's reason alone, so the caller names the path the way it shows paths.
    Problem = Data.define(:path, :detail)

    DEFAULT_DEPTH = 1
    MAX_DEPTH = 8
    GIT_ENTRY = '.git'

    # `root` is an absolute path; `depth` counts the levels under it that are searched.
    def self.scan(root, depth: DEFAULT_DEPTH)
      raise Error, "#{root}: no such directory" unless File.directory?(root)

      new.walk(root, depth)
    end

    def initialize
      @repositories = []
      @problems = []
    end

    def walk(root, depth)
      visit(root, depth)
      Result.new(repositories: @repositories, problems: @problems)
    end

    private

    # A .git file marks a linked worktree or a submodule, so any entry counts. Nothing under a
    # repository is searched: nested checkouts and vendored trees belong to it.
    def visit(directory, depth)
      return @repositories << directory if File.exist?(File.join(directory, GIT_ENTRY))
      return if depth.zero?

      subdirectories(directory).each { visit(it, depth - 1) }
    end

    # A symbolic link is never followed, so the search stays under the root and cannot loop.
    def subdirectories(directory)
      paths = Dir.children(directory).sort.map { File.join(directory, it) }
      paths.select { File.directory?(it) && !File.symlink?(it) }
    rescue SystemCallError => e
      @problems << Problem.new(path: directory, detail: e.message.sub(Error::SYSTEM_SUFFIX, ''))
      []
    end
  end
end
