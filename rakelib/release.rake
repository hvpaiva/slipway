# frozen_string_literal: true

require_relative '../lib/slipway/version'
require_relative 'support/release'

namespace :release do
  desc 'Check the tag (TAG, or the pushed tag in GitHub Actions) against Slipway::VERSION and CHANGELOG.md'
  task :verify do
    version = Slipway::VERSION
    tag = ENV['GITHUB_REF_TYPE'] == 'tag' ? ENV.fetch('GITHUB_REF_NAME', nil) : ENV.fetch('TAG', nil)
    problems = Release.verify_problems(File.read(Release::CHANGELOG), version,
                                       tag:, date: Time.now.utc.strftime('%Y-%m-%d'))
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

# Bundler's release task tags and pushes before it reaches rubygems.org, and its two subtasks can
# be run on their own; the guard stops each of them first.
%w[release:guard_clean release:source_control_push release:rubygem_push].each do |name|
  Rake::Task[name].enhance(['release:guard_ci'])
end
