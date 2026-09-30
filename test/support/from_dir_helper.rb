# frozen_string_literal: true

require 'fileutils'
require_relative 'commands_helper'

# Repositories for create project --from-dir are directories with a .git entry, answered by Git::Fake.
module FromDirHelper
  include CommandsHelper

  PROJECTS = Slipway::Resources.resolve('projects')
  HINT = "See 'slipway create --help' for usage.\n"

  # macOS keeps temporary directories under /var, a symlink to /private/var, and a directory
  # reached through the current one comes back in its real form, so the clone answers to both.
  def clone_at(runtime, path, remote: nil)
    FileUtils.mkdir_p(File.join(path, '.git'))
    [path, File.realpath(path)].uniq.each { runtime.git.add(it, status: CommandsHelper::CLEAN, remote:) }
    path
  end

  def run_create(*argv, runtime:, **)
    run_commands('create', *argv, runtime:, commands: [Slipway::Commands::Create], **)
  end

  def stored(runtime, group: nil)
    runtime.store.list(PROJECTS, group:).to_h { [it.name, [it.path, it.remote]] }
  end
end
