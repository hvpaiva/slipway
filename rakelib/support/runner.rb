# frozen_string_literal: true

require 'English'
require 'open3'

# Runs an external command for the release and repository setup code, which receive it as
# a dependency so their tests can pass a fake that records every argv instead.
class CommandRunner
  def initialize(chdir: Dir.pwd)
    @chdir = chdir
  end

  # Returns [stdout, status]. When the command fails without printing anything, its stderr
  # takes the place of stdout so the caller can report it. With +stream+ the command writes
  # to the terminal directly and stdout comes back empty; long runs use it to show progress.
  def call(argv, stream: false)
    return ['', system_status(argv)] if stream

    out, err, status = Open3.capture3(*argv, chdir: @chdir)
    [status.success? || !out.strip.empty? ? out : err, status]
  rescue Errno::ENOENT
    ["#{argv.first} is not installed\n", FailedStatus.new]
  end

  private

  def system_status(argv)
    system(*argv, chdir: @chdir, exception: false)
    $CHILD_STATUS || FailedStatus.new
  end

  # The status of a command that could not start.
  class FailedStatus
    def success? = false
    def exitstatus = 127
  end
end
