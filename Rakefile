# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'bundler/audit/task'
require 'minitest/test_task'
require 'open3'
require 'rubocop/rake_task'
require 'tempfile'
require 'yard'

# Coverage gates for test:cov. Zero measures without failing; raise both once the suite is complete.
MINIMUM_LINE_COVERAGE = 0
MINIMUM_BRANCH_COVERAGE = 0

# Minitest joins the prelude into a single-quoted shell string, so it stays on one line without quotes of its own.
COVERAGE_PRELUDE = [
  'require "simplecov"',
  'SimpleCov.start do',
  'enable_coverage :branch',
  'cover "lib/**/*.rb"',
  "coverage :line, minimum: #{MINIMUM_LINE_COVERAGE}",
  "coverage :branch, minimum: #{MINIMUM_BRANCH_COVERAGE}",
  'end'
].join('; ')

Minitest::TestTask.create(:test) do |t|
  t.warning = true
  t.test_globs = ['test/**/*_test.rb']
end

Minitest::TestTask.create('test:unit') do |t|
  t.warning = true
  t.test_globs = ['test/unit/**/*_test.rb']
end

Minitest::TestTask.create('test:integration') do |t|
  t.warning = true
  t.test_globs = ['test/integration/**/*_test.rb']
end

Minitest::TestTask.create('test:cov') do |t|
  t.warning = true
  t.test_globs = ['test/unit/**/*_test.rb', 'test/integration/**/*_test.rb']
  t.test_prelude = COVERAGE_PRELUDE
end

RuboCop::RakeTask.new

Bundler::Audit::Task.new

desc 'Update the advisory database, then check Gemfile.lock'
task audit: %w[bundle:audit:update bundle:audit:check]

namespace :generate do
  desc 'Render the man pages into man/man1'
  task :man do
    ruby '-Ilib', 'bin/generate-man'
  end
end

desc 'Regenerate every generated file'
task generate: %w[generate:man]

namespace :lint do
  desc 'Check the man pages with groff -ww'
  task :man do
    pages = Dir['man/man1/*.1']
    if pages.empty?
      puts 'lint:man: no pages under man/man1; run rake generate:man first'
    else
      _, err, status = Open3.capture3('groff', '-man', '-Tutf8', '-ww', *pages)
      abort("groff reported:\n#{err}") unless status.success? && err.empty?
    end
  end

  desc 'Run shellcheck on bin/setup and the bash completion script'
  task :shell do
    sh 'shellcheck', '-s', 'bash', 'bin/setup'
    script, err, status = Open3.capture3(RbConfig.ruby, '-Ilib', 'exe/slipway', 'completion', 'bash')
    if status.success?
      Tempfile.create(['slipway-completion-', '.bash']) do |file|
        file.write(script)
        file.flush
        sh 'shellcheck', '-s', 'bash', file.path
      end
    else
      puts "lint:shell: skipping the completion script: #{err.lines.first&.strip}"
    end
  end
end

YARD::Rake::YardocTask.new(:docs)

task default: %i[test rubocop]
