# frozen_string_literal: true

require 'fileutils'
require_relative 'cli_helper'
require_relative 'sandbox'

# Builds runtimes over a sandbox with a fake git and fixed clocks, seeds the store, and runs
# verbs through a registry that holds only the commands under test.
module CommandsHelper
  include CliHelper
  include Sandbox

  CREATED = Time.utc(2026, 9, 29, 9, 0, 0)
  NOW = Time.utc(2026, 9, 29, 12, 0, 0)
  COMMITTED = Time.utc(2026, 9, 29, 11, 15, 0)
  SHA = 'a1b2c3d4e5f60718293a4b5c6d7e8f9012345678'
  COMMIT = Slipway::Git::Commit.new(sha: SHA, short: SHA[0, 7], time: COMMITTED, author: 'Ada Lovelace',
                                    email: 'ada@example.com', subject: 'initial commit')
  CLEAN = Slipway::Git::Status.new(head: SHA[0, 7], branch: 'main', upstream: 'origin/main', ahead: 0, behind: 0)
  DIRTY = CLEAN.with(staged: 1, unstaged: 2, untracked: 3, stashes: 1)
  DETACHED = CLEAN.with(branch: nil, upstream: nil, ahead: nil, behind: nil)
  UNBORN = Slipway::Git::Status.new(head: nil, branch: 'main')
  READ_VERBS = [Slipway::Commands::Get, Slipway::Commands::Describe].freeze

  # A registry holding only +commands+, each built with a factory that returns +runtime+.
  def registry_with(*commands, runtime:)
    factory = ->(_context, _opts) { runtime }
    Slipway::CLI::Registry.new(program: Slipway::Commands::PROGRAM, version: Slipway::VERSION,
                               description: Slipway::Commands::DESCRIPTION, globals: Slipway::CLI::Globals::ALL,
                               commands: commands.map { it.command(factory) })
  end

  # A Runtime rooted in the sandbox +env+: manifests are created at CREATED and read at +now+.
  def sandbox_runtime(env, git: Slipway::Git::Fake.new, now: NOW, flags: {})
    paths = Slipway::Paths.new(env)
    config = Slipway::Config.load(paths, env:, flags:)
    clock = -> { now }
    Slipway::Runtime.new(config:, paths:, store: Slipway::Store.new(root: paths.data_home, clock: -> { CREATED }),
                         git:, inspector: Slipway::Inspector.new(git:, clock:, home: paths.home), clock:, env:)
  end

  # Registers a project at ~/dev/<name>, creates that directory and cans git's answers for it.
  # +status: nil+ leaves the directory out, so the project shows as Missing.
  def register(runtime, name, group: 'default', labels: {}, description: nil, status: CLEAN, commit: COMMIT,
               remote: nil)
    path = "~/dev/#{name}"
    directory = Slipway::Paths.expand(path, home: runtime.paths.home)
    if status
      FileUtils.mkdir_p(directory)
      runtime.git.add(directory, status:, commit: status.unborn? ? nil : commit, remote:)
    end
    runtime.store.create(Slipway::Project.new(name:, group:, labels:, path:, description:))
  end

  # Registers a project whose directory exists but whose git queries raise +error+.
  def register_failing(runtime, name, error, group: 'default')
    project = register(runtime, name, group:, status: UNBORN)
    runtime.git.fail(Slipway::Paths.expand(project.path, home: runtime.paths.home), error)
    project
  end

  def register_group(runtime, name, labels: {}, description: nil)
    runtime.store.create(Slipway::Group.new(name:, labels:, description:))
  end

  # Yields a runtime over a fresh sandbox and that sandbox's HOME.
  def with_runtime
    with_sandbox { |env| yield sandbox_runtime(env), env.fetch('HOME') }
  end

  # Runs +argv+ against a registry of the read verbs (or +commands+) bound to +runtime+.
  def run_commands(*argv, runtime:, commands: READ_VERBS, **)
    run_cli(*argv, registry: registry_with(*commands, runtime:), env: runtime.env, **)
  end
end
