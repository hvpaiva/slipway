# frozen_string_literal: true

require 'fileutils'
require_relative 'git_env'

module GitFixtures
  include GitEnv

  # Each state is built by the private method of the same name.
  STATES = %w[clean staged unstaged untracked ahead behind diverged detached unborn conflicted gone stash
              plain_dir stale stale_untracked_overlap index_lock].freeze

  # States in which origin moved on without +dir+ knowing: a second clone, "<dir>-other", pushed
  # the commit, so only a fetch shows +dir+ behind.
  module Stale
    private

    def stale(dir)
      synced(dir)
      other = "#{dir}-other"
      git!(File.dirname(dir), 'clone', '-q', '--', "#{dir}-origin.git", other)
      commit(other, 'b.txt', "b\n", 'remote work')
      git!(other, 'push', '-q', 'origin', 'main')
    end

    # The commit the fetch brings adds b.txt, which already exists here untracked.
    def stale_untracked_overlap(dir)
      stale(dir)
      write(dir, 'b.txt', "local b\n")
    end

    # A lock another git process would hold while it writes the index.
    def index_lock(dir)
      stale(dir)
      write(File.join(dir, '.git'), 'index.lock', '')
    end
  end
  include Stale

  # The tracking states (ahead, behind, diverged, gone and the stale ones) also create a bare
  # origin next to +dir+, named "<dir>-origin.git".
  def build_repo(dir, state)
    unless STATES.include?(state)
      raise ArgumentError, "unknown fixture state #{state.inspect} (known: #{STATES.join(', ')})"
    end

    send(state, dir)
    dir
  end

  private

  def write(dir, name, text)
    File.write(File.join(dir, name), text)
  end

  def commit(dir, name, text, message)
    write(dir, name, text)
    git!(dir, 'add', '--', name)
    git!(dir, 'commit', '-q', '-m', message)
  end

  def clean(dir)
    unborn(dir)
    commit(dir, 'README.md', "hello\n", 'initial commit')
  end

  def staged(dir)
    clean(dir)
    write(dir, 'new.txt', "x\n")
    git!(dir, 'add', '--', 'new.txt')
  end

  def unstaged(dir)
    clean(dir)
    write(dir, 'README.md', "hello\nchanged\n")
  end

  def untracked(dir)
    clean(dir)
    write(dir, 'notes.txt', "u\n")
  end

  def detached(dir)
    clean(dir)
    git!(dir, 'checkout', '-q', '--detach', 'HEAD')
  end

  def unborn(dir)
    FileUtils.mkdir_p(dir)
    git!(dir, 'init', '-q', '-b', 'main')
  end

  def conflicted(dir)
    clean(dir)
    git!(dir, 'checkout', '-q', '-b', 'other')
    commit(dir, 'README.md', "other\n", 'other side')
    git!(dir, 'checkout', '-q', 'main')
    commit(dir, 'README.md', "main\n", 'main side')
    _, _, status = git(dir, 'merge', '-q', 'other')
    raise "merge of #{dir} did not conflict" if status.success?
  end

  def stash(dir)
    clean(dir)
    2.times do |round|
      write(dir, 'README.md', "hello\nstash #{round}\n")
      git!(dir, 'stash', '-q')
    end
  end

  def plain_dir(dir)
    FileUtils.mkdir_p(dir)
    write(dir, 'file.txt', "plain\n")
  end

  def synced(dir)
    clean(dir)
    origin = "#{dir}-origin.git"
    FileUtils.mkdir_p(origin)
    git!(origin, 'init', '-q', '--bare')
    git!(dir, 'remote', 'add', 'origin', origin)
    git!(dir, 'push', '-q', '-u', 'origin', 'main')
  end

  def ahead(dir)
    synced(dir)
    commit(dir, 'a.txt', "a\n", 'local work')
  end

  def behind(dir)
    synced(dir)
    commit(dir, 'b.txt', "b\n", 'remote work')
    git!(dir, 'push', '-q', 'origin', 'main')
    git!(dir, 'reset', '-q', '--hard', 'HEAD~1')
  end

  def diverged(dir)
    behind(dir)
    commit(dir, 'd.txt', "d\n", 'diverging work')
  end

  def gone(dir)
    synced(dir)
    git!(dir, 'checkout', '-q', '-b', 'feature')
    git!(dir, 'push', '-q', '-u', 'origin', 'feature')
    git!(dir, 'push', '-q', 'origin', '--delete', 'feature')
    git!(dir, 'fetch', '-q', '--prune', 'origin')
  end
end
