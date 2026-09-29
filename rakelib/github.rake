# frozen_string_literal: true

require_relative 'support/github'
require_relative 'support/runner'

namespace :github do
  desc 'Configure the release environment, rulesets and security settings through gh api (safe to rerun)'
  task :setup do
    GitHub.new(runner: CommandRunner.new).setup
  rescue GitHub::Error => e
    abort "github:setup: #{e.message}"
  end
end
