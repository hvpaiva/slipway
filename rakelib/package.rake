# frozen_string_literal: true

require 'open3'
require 'tmpdir'

namespace :package do
  desc 'Build the gem, install it into an empty GEM_HOME and run the installed executable'
  task :check do
    require_tool('shellcheck')
    Dir.mktmpdir('slipway-package-') do |dir|
      gem = File.join(dir, 'slipway.gem')
      home = File.join(dir, 'home')
      Bundler.with_unbundled_env do
        sh 'gem', 'build', 'slipway.gemspec', '--output', gem
        sh 'gem', 'install', '--local', '--no-document', '--install-dir', home, '--bindir', File.join(home, 'bin'), gem
        PackageSmoke.new(home).run
      end
    end
  end
end

# Runs the installed executable with nothing but its own GEM_HOME, so a file missing from the
# gem or an undeclared dependency fails here rather than for the first user.
class PackageSmoke
  def initialize(home)
    @home = home
    @env = { 'GEM_HOME' => home, 'GEM_PATH' => home, 'RUBYOPT' => nil, 'RUBYLIB' => nil }
    @slipway = File.join(home, 'bin', 'slipway')
  end

  def run
    %w[version --help].each { |argument| slipway(argument) }
    man = slipway('man', '--path').strip
    abort "package:check: man --path printed #{man.inspect}, outside the installed gem" unless man.start_with?(@home)

    script = slipway('completion', 'bash')
    _, err, status = Open3.capture3('shellcheck', '-s', 'bash', '-', stdin_data: script)
    abort "package:check: shellcheck rejected the installed bash completion:\n#{err}" unless status.success?
    puts 'package:check: the installed gem answers version, --help, man --path and completion bash'
  end

  private

  def slipway(*arguments)
    out, err, status = Open3.capture3(@env, @slipway, *arguments)
    abort "package:check: slipway #{arguments.join(' ')} failed:\n#{err}" unless status.success?

    out
  end
end
