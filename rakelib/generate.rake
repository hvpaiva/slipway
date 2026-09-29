# frozen_string_literal: true

require 'open3'
require 'rbconfig'
require 'tmpdir'
require_relative 'support/golden'

GOLDEN_TESTS = %w[test/golden/help_test.rb test/golden/completion_test.rb test/unit/cli/manpage_test.rb].freeze

desc 'Render and lint the man pages, rewrite the golden fixtures, and list what changed'
task generate: %w[generate:man lint:man generate:golden] do
  changed, = Open3.capture2('git', 'status', '--short', '--', 'man', 'test/fixtures/golden', 'test/fixtures/man')
  puts changed.empty? ? 'No generated file changed.' : "Review these changes before committing:\n#{changed}"
end

namespace :generate do
  desc 'Rewrite the golden fixtures and remove the help and completion ones no command produces'
  task :golden do
    require_relative '../lib/slipway'

    loader = GOLDEN_TESTS.map { format('require "./%s"', it) }.join('; ')
    sh({ 'UPDATE_GOLDEN' => '1' }, RbConfig.ruby, '-w', '-Ilib', '-Itest', '-e', loader)
    registry = Slipway::Commands.registry(->(_context, _opts) { raise 'fixtures do not build a runtime' })
    expected = GoldenFixtures.expected(registry, Slipway::CLI::CompletionScripts::SHELLS)
    GoldenFixtures.remove_orphans('test/fixtures/golden', expected).each { puts "removed test/fixtures/golden/#{it}" }
  end

  desc 'Fail when man/man1 differs from what the registry renders'
  task :check do
    Dir.mktmpdir('slipway-man-') do |dir|
      out, status = Open3.capture2e(RbConfig.ruby, '-Ilib', 'bin/generate-man', dir)
      abort "bin/generate-man failed:\n#{out}" unless status.success?

      stale = (Dir.children(dir) | Dir.children('man/man1')).sort.reject do |name|
        File.file?(File.join(dir, name)) && File.file?(File.join('man/man1', name)) &&
          File.read(File.join(dir, name)) == File.read(File.join('man/man1', name))
      end
      abort "man/man1 is stale (#{stale.join(', ')}); run bundle exec rake generate and commit the result" if stale.any?
      puts 'generate:check: man/man1 matches the registry'
    end
  end
end
