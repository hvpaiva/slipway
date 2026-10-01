# frozen_string_literal: true

module Slipway
  module CLI
    # Every request goes to `PROGRAM __complete WORDS...`, so the scripts never change when
    # commands do.
    module CompletionScripts
      SHELLS = %w[bash zsh fish].freeze

      def self.render(shell, program)
        RENDERERS.fetch(shell).render(program)
      end

      # _comp_initialize is bash-completion 2.12+ and _init_completion the older name; without
      # either, COMP_WORDS is read directly.
      module Bash
        def self.render(program)
          <<~BASH
            # bash completion for #{program}                             -*- shell-script -*-
            # Install to ${XDG_DATA_HOME:-~/.local/share}/bash-completion/completions/#{program}
            # or load it with: eval "$(#{program} completion bash)"
            _#{program}() {
                # prev is filled by the bash-completion initializers; it stays local, not global.
                # shellcheck disable=SC2034
                local cur prev words cword
                if declare -F _comp_initialize >/dev/null 2>&1; then
                    _comp_initialize -n = -- "$@" || return
                elif declare -F _init_completion >/dev/null 2>&1; then
                    _init_completion -n = || return
                else
                    words=("${COMP_WORDS[@]}") cword=$COMP_CWORD cur=${COMP_WORDS[COMP_CWORD]}
                fi

                local out directive
                out=$("${words[0]}" __complete "${words[@]:1:cword-1}" "$cur" 2>/dev/null) || return
                directive=${out##*$'\\n':}
                [[ $out == :* ]] && directive=${out#:}
                out=${out%$'\\n'*}
                [[ $out == :* ]] && out=""

                COMPREPLY=()
                local line
                if [[ -n $out ]]; then
                    while IFS= read -r line; do COMPREPLY+=("${line%%$'\\t'*}"); done <<<"$out"
                fi
                # readline still breaks the word at "=", so "--flag=" must leave the replies.
                local i prefix=""
                [[ $cur == -*=* ]] && prefix=${cur%%=*}=
                if [[ -n $prefix && $COMP_WORDBREAKS == *=* ]]; then
                    for i in "${!COMPREPLY[@]}"; do COMPREPLY[i]=${COMPREPLY[i]#"$prefix"}; done
                fi
                (( directive & 2 )) && compopt -o nospace 2>/dev/null
                if (( ${#COMPREPLY[@]} == 0 )) && ! (( directive & 4 )); then
                    # The file name is what follows "--flag=": the filedir helpers read cur.
                    cur=${cur#"$prefix"}
                    if declare -F _comp_compgen_filedir >/dev/null 2>&1; then
                        _comp_compgen_filedir
                    elif declare -F _filedir >/dev/null 2>&1; then
                        _filedir
                    elif ! compopt -o default 2>/dev/null; then
                        # Not mapfile: bash 3.2, macOS's /bin/bash, has neither it nor compopt.
                        while IFS= read -r line; do COMPREPLY+=("$line"); done < <(compgen -f -- "$cur")
                    fi
                    if [[ -n $prefix && $COMP_WORDBREAKS != *=* ]]; then
                        for i in "${!COMPREPLY[@]}"; do COMPREPLY[i]=$prefix${COMPREPLY[i]}; done
                    fi
                fi
            }
            complete -F _#{program} #{program}
          BASH
        end
      end

      # Builds `value:description` pairs for _describe; a `--flag=` prefix is moved into
      # IPREFIX with compset so the values alone are listed.
      module Zsh
        def self.render(program)
          <<~ZSH
            #compdef #{program}
            # zsh completion for #{program}. Install it as _#{program} in a directory on your fpath,
            # such as ~/.zfunc/_#{program} with `fpath+=~/.zfunc` before compinit, or load it
            # with: source <(#{program} completion zsh)
            compdef _#{program} #{program}

            _#{program}() {
                local -a lines candidates describe_opts
                local line directive prefix="" ret=1
                lines=("${(@f)$(${words[1]} __complete "${(@)words[2,CURRENT-1]}" "${words[CURRENT]}" 2>/dev/null)}")
                (( ${#lines} )) || return 1
                directive=${lines[-1]#:}
                lines=("${(@)lines[1,-2]}")
                compset -P '--[^=]#=' && prefix=$IPREFIX
                for line in "${lines[@]}"; do
                    [[ -z $line ]] && continue
                    line=${line#"$prefix"}
                    if [[ $line == *$'\\t'* ]]; then
                        candidates+=("${${line%%$'\\t'*}//:/\\\\:}:${line#*$'\\t'}")
                    else
                        candidates+=("${line//:/\\\\:}")
                    fi
                done
                (( directive & 2 )) && describe_opts+=(-S '')
                if (( ${#candidates} )); then
                    _describe -t values '#{program}' candidates "${describe_opts[@]}" && ret=0
                fi
                if (( ret )) && ! (( directive & 4 )); then
                    _files && ret=0
                fi
                return ret
            }

            if [[ "$funcstack[1]" == "_#{program}" ]]; then
                _#{program} "$@"
            fi
          ZSH
        end
      end

      # Both completion conditions call __PROGRAM_complete, so the answer is cached per command
      # line. fish reads `value<TAB>description` lines natively. It has no switch to leave out the
      # space after a candidate: it adds none only after one that ends in one of @=/:., or while
      # several remain. So, as cobra does, a lone candidate under the no-space directive gets a
      # copy with a dot after it, and fish inserts what the two share.
      module Fish
        def self.render(program)
          <<~FISH
            # fish completion for #{program}. Install it to ~/.config/fish/completions/#{program}.fish
            function __#{program}_complete
                set -l line (commandline -cp)
                if set -q __#{program}_line; and test "$__#{program}_line" = "$line"
                    return 0
                end
                set -g __#{program}_line $line
                set -g __#{program}_directive 4
                set -g __#{program}_results
                set -l tokens (commandline -opc)
                set -l program $tokens[1]
                set -e tokens[1]
                set -l lines ($program __complete $tokens (commandline -ct) 2>/dev/null)
                or return 0
                if test (count $lines) -gt 0
                    set -g __#{program}_directive (string replace -r '^:' '' -- $lines[-1])
                    set -e lines[-1]
                    set -g __#{program}_results $lines
                end
                if test (count $__#{program}_results) -eq 1; and test (math "bitand($__#{program}_directive, 2)") -ne 0
                    set -l value (string split -m 1 \\t -- $__#{program}_results[1])[1]
                    if not string match -qr '[@=/:.,]$' -- $value
                        set -g __#{program}_results $value $value.
                    end
                end
            end

            function __#{program}_wants_files
                __#{program}_complete
                test (count $__#{program}_results) -eq 0
                and test (math "bitand($__#{program}_directive, 4)") -eq 0
            end

            # fish replaces the whole token, so a --flag= value has its path completed and the flag
            # put back in front of each one.
            function __#{program}_complete_path
                set -l token (commandline -ct)
                if string match -qr -- '^-[^=]*=' $token
                    set -l flag (string replace -r -- '=.*' '=' $token)
                    __fish_complete_path (string replace -r -- '^[^=]*=' '' $token) | string replace -r -- '^' $flag
                else
                    __fish_complete_path $token
                end
            end

            complete -c #{program} -e
            complete -c #{program} -n '__#{program}_complete' -f -a '$__#{program}_results'
            complete -c #{program} -n '__#{program}_wants_files' -a '(__#{program}_complete_path)'
          FISH
        end
      end

      RENDERERS = { 'bash' => Bash, 'zsh' => Zsh, 'fish' => Fish }.freeze
    end
  end
end
