# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'bundler/audit/task'
require 'minitest/test_task'
require 'open3'
require 'rubocop/rake_task'
require 'tempfile'
require 'yard'

# Coverage gates for test:cov. Each sits at least two points under what test:cov measures, overall
# or for the least covered file, and is raised when the measured figure rises.
MINIMUM_LINE_COVERAGE = 97
MINIMUM_BRANCH_COVERAGE = 96
MINIMUM_LINE_COVERAGE_BY_FILE = 93
MINIMUM_BRANCH_COVERAGE_BY_FILE = 85

# Minitest joins the prelude into a single-quoted shell string, so it stays on one line without
# quotes of its own. Bundler loads version.rb through the gemspec before SimpleCov starts, so
# that file would count as never run; skip leaves it out. Without merging, the gates judge this
# run alone, never a result left in coverage/ by an earlier one.
COVERAGE_PRELUDE = [
  'require "simplecov"',
  'SimpleCov.start do',
  'merging false',
  'enable_coverage :branch',
  'cover "lib/**/*.rb"',
  'skip "lib/slipway/version.rb"',
  "coverage(:line) { minimum #{MINIMUM_LINE_COVERAGE}; minimum #{MINIMUM_LINE_COVERAGE_BY_FILE}, per: :file }",
  "coverage(:branch) { minimum #{MINIMUM_BRANCH_COVERAGE}; minimum #{MINIMUM_BRANCH_COVERAGE_BY_FILE}, per: :file }",
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
  t.test_globs = ['test/unit/**/*_test.rb', 'test/golden/**/*_test.rb']
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

def require_tool(tool)
  return if system(tool, '--version', out: File::NULL, err: File::NULL)

  abort "#{tool} is not installed; install it with your package manager (pacman, apt or brew)"
end

namespace :lint do
  desc 'Check the man pages with groff -ww'
  task :man do
    require_tool('groff')
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
    require_tool('shellcheck')
    sh 'shellcheck', '-s', 'bash', 'bin/setup'
    script, err, status = Open3.capture3(RbConfig.ruby, '-Ilib', 'exe/slipway', 'completion', 'bash')
    abort "lint:shell: slipway completion bash failed: #{err.lines.first&.strip}" unless status.success?

    Tempfile.create(['slipway-completion-', '.bash']) do |file|
      file.write(script)
      file.flush
      sh 'shellcheck', '-s', 'bash', file.path
    end
  end
end

YARD::Rake::YardocTask.new(:docs)

task default: %i[test rubocop]
