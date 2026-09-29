# frozen_string_literal: true

require 'open3'
require 'rbconfig'
require 'tmpdir'

# Drives the generated completion scripts inside real shells. A stub `slipway` on PATH
# answers `__complete` from the FixtureRegistry, so no store or git is involved.
module ShellHarness
  BASH_COMPLETION = '/usr/share/bash-completion/bash_completion'
  STUB = <<~RUBY
    #!%<ruby>s
    # frozen_string_literal: true

    $LOAD_PATH.unshift(%<lib>p, %<test>p)
    require 'slipway'
    require 'support/fixture_registry'

    registry = FixtureRegistry.new.registry
    exit Slipway::CLI::Runner.new(registry, Slipway::CLI::Context.system).run(ARGV)
  RUBY

  # Yields a directory holding bin/slipway, the three scripts, and an env whose PATH
  # finds the stub first. Bundler's variables are dropped so the stub loads plain Ruby.
  def with_completion_stub
    Dir.mktmpdir('slipway-shell-') do |dir|
      write_stub(dir)
      Slipway::CLI::CompletionScripts::SHELLS.each do |shell|
        File.write(File.join(dir, "slipway.#{shell}"), Slipway::CLI::CompletionScripts.render(shell, 'slipway'))
      end
      yield dir, stub_env(dir)
    end
  end

  # COMPREPLY for +line+ (a command line up to the cursor) through the bash script.
  def bash_completions(dir, line, env, bash_completion: false)
    prelude = bash_completion ? "source #{BASH_COMPLETION}" : ''
    script = <<~BASH
      #{prelude}
      source "$1/slipway.bash"
      read -ra COMP_WORDS <<<"$2"
      [[ $2 == *" " ]] && COMP_WORDS+=("")
      COMP_CWORD=$(( ${#COMP_WORDS[@]} - 1 ))
      COMP_LINE=$2 COMP_POINT=${#2}
      _slipway "${COMP_WORDS[0]}" "${COMP_WORDS[COMP_CWORD]}" "${COMP_WORDS[COMP_CWORD-1]}"
      printf '%s\\n' "${COMPREPLY[@]}"
    BASH
    run_shell(env, 'bash', '--norc', '--noprofile', '-c', script, 'harness', dir, line)
  end

  # Candidates fish offers for +line+, as `value<TAB>description` lines.
  def fish_completions(dir, line, env)
    script = "source #{File.join(dir, 'slipway.fish')}; complete -C #{line.inspect}"
    run_shell(env, 'fish', '--no-config', '-c', script)
  end

  # The listing an interactive zsh prints for +line+ followed by TAB, driven through zpty.
  def zsh_completions(dir, line, env)
    script = <<~ZSH
      zmodload zsh/zpty
      mkdir -p "$1/zfunc" && cp "$1/slipway.zsh" "$1/zfunc/_slipway"
      zpty -b z zsh -f -i
      zpty -w z "fpath=($1/zfunc \\$fpath); autoload -Uz compinit; compinit -u -d $1/zcompdump"
      zpty -w z 'zstyle ":completion:*" force-list always; zstyle ":completion:*" menu no; unsetopt listambiguous; setopt nolistbeep; PS1="% "'
      sleep 0.5; while zpty -r -t z line; do :; done
      zpty -w -n z "$2"$'\\t'; sleep 1.5
      out=""; while zpty -r -t z line; do out+=$line; done
      zpty -d z
      print -r -- "$out" | sed 's/\\r//g; s/\\x1b\\[[0-9;?]*[A-Za-z]//g' | grep -v '^% ' | grep -v '^$'
    ZSH
    run_shell(env, 'zsh', '-f', '-c', script, 'harness', dir, line)
  end

  # Set to anything non-empty, this turns a missing zsh or fish into a failure instead of a
  # skip; the CI completions job sets it after installing both shells.
  REQUIRE_SHELLS = 'SLIPWAY_REQUIRE_SHELLS'

  # True when +binary+ is on PATH. A shell missing locally is a reason to skip its tests;
  # under REQUIRE_SHELLS it is a misconfigured runner, so the tests fail instead.
  def shell_installed?(binary)
    return true if ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).any? { File.executable?(File.join(it, binary)) }
    return false if ENV.fetch(REQUIRE_SHELLS, '').empty? || !Slipway::CLI::CompletionScripts::SHELLS.include?(binary)

    flunk "#{binary} is not installed; #{REQUIRE_SHELLS} is set, so every shell the completion scripts target " \
          'must be present'
  end

  private

  def write_stub(dir)
    bin = File.join(dir, 'bin')
    Dir.mkdir(bin)
    stub = format(STUB, ruby: RbConfig.ruby, lib: File.expand_path('../../lib', __dir__),
                        test: File.expand_path('..', __dir__))
    File.write(File.join(bin, 'slipway'), stub)
    File.chmod(0o755, File.join(bin, 'slipway'))
  end

  def stub_env(dir)
    ENV.to_h.reject { |key, _| key.start_with?('BUNDLE', 'RUBY') }
       .merge('PATH' => "#{File.join(dir, 'bin')}#{File::PATH_SEPARATOR}#{ENV.fetch('PATH')}", 'TERM' => 'dumb')
  end

  def run_shell(env, *argv)
    out, err, status = Open3.capture3(env, *argv, unsetenv_others: true)
    raise "#{argv.first} failed (#{status.exitstatus}): #{err}" unless status.success?

    out.lines(chomp: true)
  end
end
