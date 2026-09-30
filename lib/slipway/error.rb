# frozen_string_literal: true

module Slipway
  # Base class for every failure reported to the user. The front controller prints each of
  # `problems` on its own `error:` line.
  class Error < StandardError
    # Ruby appends ` @ rb_sysopen - /path` to a SystemCallError; the user needs the path
    # they typed and the strerror text alone.
    SYSTEM_SUFFIX = / @ \S+ - .*\z/m

    def self.from_system_call(error, path)
      new("#{path}: #{error.message.sub(SYSTEM_SUFFIX, '')}")
    end

    def initialize(message = nil, problems: nil)
      @problems = problems&.dup&.freeze
      super(problems ? problems.join("\n") : message)
    end

    def problems = @problems || [message]

    def exit_status = 1

    # Usage errors point at a help page; every other error prints its message alone.
    def hint = nil
  end
end
