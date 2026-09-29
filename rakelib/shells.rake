# frozen_string_literal: true

require 'open3'
require 'rbconfig'

namespace :test do
  desc 'Run the completion scripts in real bash, zsh and fish (locally, or in docker when a shell is missing)'
  task :shells do
    if ShellTests.installed?('zsh') && ShellTests.installed?('fish')
      sh({ ShellTests::REQUIRE => '1' }, RbConfig.ruby, '-Ilib', '-Itest', ShellTests::TEST)
    elsif system('docker', 'info', out: File::NULL, err: File::NULL)
      ShellTests.run_in_docker
    else
      abort 'test:shells needs zsh and fish on PATH, or a running docker: install zsh and fish ' \
            '(pacman -S zsh fish, apt install zsh fish, brew install zsh fish) or docker'
    end
  end
end

# Runs the completion scripts test where zsh and fish exist: here, or in a docker image built
# on the fly from ruby:4.0 with the three shells and ShellCheck, as on the CI runner.
module ShellTests
  extend FileUtils

  TEST = 'test/unit/cli/completion_scripts_test.rb'
  REQUIRE = 'SLIPWAY_REQUIRE_SHELLS'
  IMAGE = 'slipway-shells:ruby-4.0'
  GEMS_VOLUME = 'slipway-shells-gems'
  # /gems is world-writable, so the named volume mounted there starts with that mode and the
  # bundle, installed as the calling user, survives between runs.
  DOCKERFILE = <<~DOCKERFILE
    FROM ruby:4.0
    RUN apt-get update && apt-get install -y --no-install-recommends zsh fish bash-completion shellcheck \\
        && rm -rf /var/lib/apt/lists/* && mkdir /gems && chmod 1777 /gems
  DOCKERFILE

  module_function

  def installed?(binary)
    ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).any? { File.executable?(File.join(it, binary)) }
  end

  def run_in_docker
    puts "test:shells: zsh or fish is missing here, so the test runs in docker (#{IMAGE})"
    out, status = Open3.capture2e('docker', 'build', '--quiet', '--tag', IMAGE, '-', stdin_data: DOCKERFILE)
    abort "docker build failed:\n#{out}" unless status.success?

    sh 'docker', 'run', '--rm', '--user', "#{Process.uid}:#{Process.gid}", '-v', "#{Dir.pwd}:/w", '-w', '/w',
       '-v', "#{GEMS_VOLUME}:/gems", '-e', 'BUNDLE_PATH=/gems', '-e', 'HOME=/tmp',
       '-e', "#{REQUIRE}=1", '-e', 'BUNDLE_FROZEN=1', IMAGE,
       'sh', '-c', "bundle install --quiet && bundle exec ruby -Ilib -Itest #{TEST}"
  end
end
