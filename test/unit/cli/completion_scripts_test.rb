# frozen_string_literal: true

require 'test_helper'

class CompletionScriptsTest < Minitest::Test
  include ShellHarness

  SCRIPTS = Slipway::CLI::CompletionScripts

  def test_render_dispatches_on_the_shell_name
    assert_equal SCRIPTS::Bash.render('slipway'), SCRIPTS.render('bash', 'slipway')
    assert_equal SCRIPTS::Zsh.render('slipway'), SCRIPTS.render('zsh', 'slipway')
    assert_equal SCRIPTS::Fish.render('slipway'), SCRIPTS.render('fish', 'slipway')
    assert_raises(KeyError) { SCRIPTS.render('powershell', 'slipway') }
  end

  def test_bash_names_its_install_path_and_registers_the_function
    script = SCRIPTS::Bash.render('slipway')

    assert_equal '# bash completion for slipway                             -*- shell-script -*-', script.lines[0].chomp
    assert_equal '# Install to ${XDG_DATA_HOME:-~/.local/share}/bash-completion/completions/slipway',
                 script.lines[1].chomp
    assert_includes script, '_comp_initialize -n = -- "$@" || return'
    assert_includes script, '_init_completion -n = || return'
    assert_includes script, 'compopt -o default'
    assert_equal 'complete -F _slipway slipway', script.lines.last.chomp
  end

  def test_zsh_names_its_install_path_and_falls_back_to_files
    script = SCRIPTS::Zsh.render('slipway')

    assert_equal '#compdef slipway', script.lines[0].chomp
    assert_includes script, 'such as ~/.zfunc/_slipway with `fpath+=~/.zfunc` before compinit'
    assert_includes script, 'compdef _slipway slipway'
    assert_includes script, "compset -P '--[^=]#='"
    assert_includes script, '_describe -t values'
    assert_includes script, '_files && ret=0'
  end

  def test_fish_names_its_install_path_and_falls_back_to_paths
    script = SCRIPTS::Fish.render('slipway')

    assert_equal '# fish completion for slipway. Install it to ~/.config/fish/completions/slipway.fish',
                 script.lines[0].chomp
    assert_includes script, 'commandline -opc'
    assert_includes script, 'commandline -ct'
    assert_includes script, "complete -c slipway -n '__slipway_complete' -f -a '$__slipway_results'"
    assert_includes script, '__fish_complete_path (commandline -ct)'
  end

  def test_program_name_is_substituted_everywhere
    %w[bash zsh fish].each do |shell|
      script = SCRIPTS.render(shell, 'proj')

      assert_includes script, '_proj'
      assert_includes script, '__complete'
      refute_includes script, 'slipway'
    end
  end

  def test_bash_script_passes_shellcheck
    skip 'shellcheck is not installed' unless shell_installed?('shellcheck')

    with_completion_stub do |dir, env|
      _, err, status = Open3.capture3(env, 'shellcheck', '-s', 'bash', File.join(dir, 'slipway.bash'))

      assert_predicate status, :success?, err
    end
  end

  def test_bash_completes_in_a_real_shell_with_and_without_bash_completion
    modes = [false]
    modes << true if File.exist?(ShellHarness::BASH_COMPLETION)
    with_completion_stub do |dir, env|
      modes.each do |bash_completion|
        assert_equal %w[projects groups], bash_completions(dir, 'slipway get ', env, bash_completion:)
        assert_equal %w[alpha beta], bash_completions(dir, 'slipway get projects ', env, bash_completion:)
        assert_equal %w[json], bash_completions(dir, 'slipway get projects --output=j', env, bash_completion:)
        assert_equal %w[view path], bash_completions(dir, 'slipway config ', env, bash_completion:)
        assert_equal ['get'], bash_completions(dir, 'slipway ge', env, bash_completion:)
      end
    end
  end

  def test_bash_leaves_out_the_space_only_when_the_directive_says_so
    with_completion_stub do |dir, env|
      assert_equal [%w[projects], ['-o nospace']], answer(dir, 'slipway explain proj', env)
      assert_equal [%w[projects.kind projects.spec], ['-o nospace']], answer(dir, 'slipway explain projects.', env)
      assert_equal [%w[projects.kind], []], answer(dir, 'slipway explain projects.k', env)
    end
  end

  def test_bash_strips_descriptions
    with_completion_stub do |dir, env|
      assert_equal %w[get create explain config help version completion man], bash_completions(dir, 'slipway ', env)
    end
  end

  def test_zsh_lists_candidates_with_descriptions
    skip 'zsh is not installed' unless shell_installed?('zsh')

    with_completion_stub do |dir, env|
      listing = zsh_completions(dir, 'slipway get ', env).join("\n")

      assert_match(/projects/, listing)
      assert_match(/groups/, listing)
      assert_match(/get\s+-- Display one or many resources/, zsh_completions(dir, 'slipway ge', env).join("\n"))
    end
  end

  def test_zsh_leaves_out_the_space_only_when_the_directive_says_so
    skip 'zsh is not installed' unless shell_installed?('zsh')

    with_completion_stub do |dir, env|
      assert_equal 'slipway explain projects', zsh_buffer(dir, 'slipway explain proj', env)
      assert_equal 'slipway explain projects.kind ', zsh_buffer(dir, 'slipway explain projects.k', env)
    end
  end

  def test_fish_lists_candidates_with_descriptions
    skip 'fish is not installed' unless shell_installed?('fish')

    with_completion_stub do |dir, env|
      assert_equal %w[groups projects], fish_completions(dir, 'slipway get ', env).sort
      assert_equal ["get\tDisplay one or many resources"], fish_completions(dir, 'slipway ge', env)
      assert_equal %w[alpha beta], fish_completions(dir, 'slipway get projects ', env).sort
    end
  end

  # fish adds no space after a candidate that is not the only one, so the directive doubles a
  # lone candidate, the second copy ending in a dot.
  def test_fish_leaves_out_the_space_only_when_the_directive_says_so
    skip 'fish is not installed' unless shell_installed?('fish')

    with_completion_stub do |dir, env|
      assert_equal %w[projects projects.], fish_completions(dir, 'slipway explain proj', env)
      assert_equal %w[projects.kind projects.spec], fish_completions(dir, 'slipway explain projects.', env)
      assert_equal %w[projects.kind], fish_completions(dir, 'slipway explain projects.k', env)
    end
  end

  private

  def answer(dir, line, env) = [bash_completions(dir, line, env), bash_compopt(dir, line, env)]
end
