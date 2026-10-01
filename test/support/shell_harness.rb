# frozen_string_literal: true

require 'open3'
require 'rbconfig'
require 'tmpdir'

# A stub `slipway` on PATH answers `__complete` from the FixtureRegistry, so no store or git
# is involved.
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

  # Bundler's variables are dropped so the stub loads plain Ruby.
  def with_completion_stub
    Dir.mktmpdir('slipway-shell-') do |dir|
      write_stub(dir)
      Slipway::CLI::CompletionScripts::SHELLS.each do |shell|
        File.write(File.join(dir, "slipway.#{shell}"), Slipway::CLI::CompletionScripts.render(shell, 'slipway'))
      end
      yield dir, stub_env(dir)
    end
  end

  # bash resets COMP_WORDBREAKS when it starts, so `wordbreaks:` is assigned inside the script,
  # and COLUMNS is fixed so that a listing (`type: 63`) does not depend on the terminal.
  def bash_completions(dir, line, env, **) = bash_answer(dir, line, env, **).first

  # compopt changes nothing unless readline started the completion, so a function in its place
  # records what the completion function asked of it.
  def bash_compopt(dir, line, env) = bash_answer(dir, line, env).last

  # The replies, a line with `--`, then one line per compopt call.
  BASH_ANSWER = <<~'BASH'
    [[ -n $3 ]] && COMP_WORDBREAKS=$3; [[ -n $4 ]] && COMP_TYPE=$4; COLUMNS=80
    source "$1/slipway.bash"
    asked=()
    compopt() { asked+=("$*"); builtin compopt "$@"; }
    read -ra COMP_WORDS <<<"$2"
    [[ $2 == *" " ]] && COMP_WORDS+=("")
    COMP_CWORD=$(( ${#COMP_WORDS[@]} - 1 ))
    COMP_LINE=$2 COMP_POINT=${#2}
    __start_slipway "${COMP_WORDS[0]}" "${COMP_WORDS[COMP_CWORD]}" "${COMP_WORDS[COMP_CWORD-1]}"
    printf '%s\n' "${COMPREPLY[@]}"
    printf -- '--\n'
    for option in "${asked[@]}"; do printf '%s\n' "$option"; done
  BASH

  def fish_completions(dir, line, env)
    script = "source #{File.join(dir, 'slipway.fish')}; complete -C #{line.inspect}"
    run_shell(env, 'fish', '--no-config', '-c', script)
  end

  def zsh_completions(dir, line, env)
    run_shell(env, 'zsh', '-f', '-c', ZSH_LISTING, 'harness', dir, line, '')
  end

  # The command line as TAB leaves it, trailing space included, read back by a widget bound to
  # Ctrl-T, which unlike Ctrl-X starts no other binding.
  def zsh_buffer(dir, line, env)
    listing = run_shell(env, 'zsh', '-f', '-c', ZSH_LISTING, 'harness', dir, line, "\C-x\C-b")
    listing.join("\n")[/buffer:\[(.*)\]/, 1]
  end

  # The harness directory travels in the environment, and is the working directory of the zsh in
  # the pty, so every line typed into it stays short of the 80 columns zsh assumes there. The
  # keys in $3 are typed once the pty has gone quiet after the TAB, so they never arrive while
  # the completion is still running. They are Ctrl-X Ctrl-B rather than a single control key,
  # because a BSD terminal (macOS) takes Ctrl-T as its status character. The listing is read
  # until the pty has been quiet for a second.
  ZSH_LISTING = <<~'ZSH'
    zmodload zsh/zpty
    mkdir -p "$1/zfunc" && cp "$1/slipway.zsh" "$1/zfunc/_slipway"
    export HARNESS_DIR="$1"
    zpty -b z zsh -f -i
    zpty -w z 'fpath=($HARNESS_DIR/zfunc $fpath); autoload -Uz compinit; compinit -u -d $HARNESS_DIR/zcompdump'
    zpty -w z 'zstyle ":completion:*" force-list always; zstyle ":completion:*" menu no'
    zpty -w z 'show-buffer() { zle -M "buffer:[$BUFFER]" }; zle -N show-buffer; bindkey "^X^B" show-buffer'
    zpty -w z 'cd $HARNESS_DIR'
    zpty -w z 'unsetopt listambiguous; setopt nolistbeep; PS1="% "; print $(( 6 * 7 ))'
    for i in {1..200}; do
      if zpty -r -t z line; then [[ ${line%%$'\r'*} == 42 ]] && break; else sleep 0.05; fi
    done
    while zpty -r -t z line; do :; done
    drain() {
      local quiet=0
      while (( quiet < 10 )); do
        if zpty -r -t z line; then out+=$line; quiet=0; else sleep 0.1; (( quiet++ )); fi
      done
    }
    out=""; zpty -w -n z "$2"$'\t'; drain
    [[ -n $3 ]] && { zpty -w -n z "$3"; drain; }
    zpty -d z
    print -r -- "$out" | sed 's/\r//g; s/\x1b\[[0-9;?]*[A-Za-z]//g' | grep -v '^% ' | grep -v '^$'
  ZSH

  # Set to anything non-empty, this turns a missing zsh or fish into a failure instead of a
  # skip; the CI completions job sets it after installing both shells.
  REQUIRE_SHELLS = 'SLIPWAY_REQUIRE_SHELLS'

  # A shell missing locally is a reason to skip its tests; under REQUIRE_SHELLS it is a
  # misconfigured runner, so the tests fail instead.
  def shell_installed?(binary)
    return true if ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).any? { File.executable?(File.join(it, binary)) }
    return false if ENV.fetch(REQUIRE_SHELLS, '').empty? || !Slipway::CLI::CompletionScripts::SHELLS.include?(binary)

    flunk "#{binary} is not installed; #{REQUIRE_SHELLS} is set, so every shell the completion scripts target " \
          'must be present'
  end

  private

  def bash_answer(dir, line, env, bash_completion: false, wordbreaks: nil, type: nil)
    script = bash_completion ? "source #{BASH_COMPLETION}\n#{BASH_ANSWER}" : BASH_ANSWER
    lines = run_shell(env, 'bash', '--norc', '--noprofile', '-c', script, 'harness', dir, line, wordbreaks.to_s,
                      type.to_s)
    [lines.take_while { it != '--' }, lines.drop_while { it != '--' }.drop(1)]
  end

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
