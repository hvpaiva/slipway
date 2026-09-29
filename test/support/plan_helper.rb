# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'

# Plans a project whose repository Git::Fake describes, through the Inspector, so a test sees
# what diff, get and describe see.
module PlanHelper
  PATH = '~/dev/hldr'
  CLEAN = CommandsHelper::CLEAN
  BEHIND = CLEAN.with(behind: 3)
  COMMIT = CommandsHelper::COMMIT

  def setup
    @home = Dir.mktmpdir('slipway-plan-')
    @git = Slipway::Git::Fake.new
    @inspector = Slipway::Inspector.new(git: @git, clock: -> { CommandsHelper::NOW }, home: @home)
  end

  def teardown
    FileUtils.remove_entry(@home)
  end

  # +origin+ is the remote git answers with, and +spec+ the fields the manifest declares. +error+
  # makes git fail with it; +absent+ leaves the directory out.
  def plan(status = CLEAN, commit: COMMIT, origin: nil, operation: nil, error: nil, absent: false, path: PATH, **spec)
    directory = Slipway::Paths.expand(path, home: @home)
    unless absent
      FileUtils.mkdir_p(directory)
      error ? @git.fail(directory, error) : @git.add(directory, status:, commit:, remote: origin, operation:)
    end
    Slipway::Plan.for(@inspector.examine(Slipway::Project.new(name: 'hldr', path:, **spec)))
  end

  def lines(result) = result.items.map { [it.type, it.message, it.command].compact }

  def kinds(result) = [result.actions, result.skips, result.reports].map { |items| items.map(&:type) }
end
