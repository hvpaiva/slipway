# frozen_string_literal: true

require_relative '../lib/slipway/version'
require_relative 'support/changelog'

namespace :release do
  desc 'Check the tag (TAG, or the pushed tag in GitHub Actions) against Slipway::VERSION and CHANGELOG.md'
  task :verify do
    version = Slipway::VERSION
    tag = ENV['GITHUB_REF_TYPE'] == 'tag' ? ENV.fetch('GITHUB_REF_NAME', nil) : ENV.fetch('TAG', nil)
    problems = Changelog.release_problems(File.read('CHANGELOG.md'), version).map { "CHANGELOG.md has #{it}" }
    problems.unshift("tag #{tag} does not match Slipway::VERSION #{version}") if tag && tag != "v#{version}"
    unless problems.empty?
      prefix = ENV['GITHUB_ACTIONS'] == 'true' ? '::error::' : 'release:verify: '
      abort problems.map { "#{prefix}#{it}" }.join("\n")
    end

    File.write(ENV.fetch('GITHUB_OUTPUT'), "version=#{version}\n", mode: 'a') if ENV.key?('GITHUB_OUTPUT')
    puts "release:verify: #{tag || 'no tag given'}, Slipway::VERSION #{version} and CHANGELOG.md agree"
  end

  desc 'Refuse rake release outside GitHub Actions, where only the tag workflow publishes'
  task :guard_ci do
    abort 'rake release runs only inside GitHub Actions; use bin/release' unless ENV['GITHUB_ACTIONS'] == 'true'
  end
end

# Bundler's release task tags and pushes before it reaches rubygems.org; the guard stops it first.
Rake::Task['release:guard_clean'].enhance(['release:guard_ci'])
