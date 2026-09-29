# frozen_string_literal: true

module Slipway
  # Base class for every failure Slipway reports to the user; exits with status 1. An error
  # may carry several +problems+, which the front controller prints one `error:` line each.
  class Error < StandardError
    # Ruby appends ` @ rb_sysopen - /path` to a SystemCallError; the user needs the path
    # they typed and the strerror text alone.
    SYSTEM_SUFFIX = / @ \S+ - .*\z/m

    # An Error reading `<path>: <strerror>` for a SystemCallError met at +path+.
    def self.from_system_call(error, path)
      new("#{path}: #{error.message.sub(SYSTEM_SUFFIX, '')}")
    end

    # +problems+ turns one exception into several report lines; the message then joins them.
    def initialize(message = nil, problems: nil)
      @problems = problems&.dup&.freeze
      super(problems ? problems.join("\n") : message)
    end

    # The lines the front controller reports, each on its own `error:` line.
    def problems = @problems || [message]

    # The process exit status this failure maps to.
    def exit_status = 1

    # Usage errors point at a help page; every other error prints its message alone.
    def hint = nil
  end
end
