# frozen_string_literal: true

require_relative 'git/errors'
require_relative 'git/runner'
require_relative 'git/status'
require_relative 'git/commit'
require_relative 'git/repository'
require_relative 'git/fake'

module Slipway
  # Reads the state of local repositories through the git executable: a Runner that spawns
  # it safely, a Repository that asks the questions Slipway needs, and a Fake for tests.
  module Git
  end
end
