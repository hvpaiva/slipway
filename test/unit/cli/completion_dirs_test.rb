# frozen_string_literal: true

require 'test_helper'

# "su" matches both sub/ and subfile.yaml, so only the directory may come back.
class CompletionDirsTest < Minitest::Test
  include ShellHarness

  def test_bash_completes_only_directories_when_the_directive_says_so
    modes = [false]
    modes << true if File.exist?(ShellHarness::BASH_COMPLETION)
    with_directory_and_file do |dir, env, sub|
      line = 'slipway create projects x --from-dir'
      modes.each do |bash_completion|
        assert_equal [sub], bash_completions(dir, "#{line} #{dir}/su", env, bash_completion:)
        assert_equal [sub], bash_completions(dir, "#{line}=#{dir}/su", env, bash_completion:)
      end
    end
  end

  def test_zsh_completes_only_directories_when_the_directive_says_so
    skip 'zsh is not installed' unless shell_installed?('zsh')

    with_directory_and_file do |dir, env|
      assert_equal 'slipway create projects x --from-dir sub/',
                   zsh_buffer(dir, 'slipway create projects x --from-dir su', env)
      assert_equal 'slipway create projects x --from-dir=sub/',
                   zsh_buffer(dir, 'slipway create projects x --from-dir=su', env)
    end
  end

  def test_fish_completes_only_directories_when_the_directive_says_so
    skip 'fish is not installed' unless shell_installed?('fish')

    with_directory_and_file do |dir, env, sub|
      values = ->(line) { fish_completions(dir, line, env).map { it.split("\t").first } }

      assert_equal ["#{sub}/"], values.call("slipway create projects x --from-dir #{dir}/su")
      assert_equal ["--from-dir=#{sub}/"], values.call("slipway create projects x --from-dir=#{dir}/su")
    end
  end

  private

  def with_directory_and_file
    with_completion_stub do |dir, env|
      sub = File.join(dir, 'sub')
      Dir.mkdir(sub)
      File.write(File.join(dir, 'subfile.yaml'), '')
      yield dir, env, sub
    end
  end
end
