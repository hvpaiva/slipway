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
      # either, COMP_WORDS is read directly. The function names and the words, cur and out
      # variables follow cobra's bash script, so tools built around cobra's completion, such as
      # ble.sh, show the descriptions.
      module Bash
        def self.render(program)
          <<~BASH
            # bash completion for #{program}                             -*- shell-script -*-
            # Install to ${XDG_DATA_HOME:-~/.local/share}/bash-completion/completions/#{program}
            # or load it with: eval "$(#{program} completion bash)"
            __start_#{program}() {
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
                __#{program}_get_completion_results || return
                (( directive & 2 )) && compopt -o nospace 2>/dev/null
                COMPREPLY=()
                if [[ -n $out ]]; then
                    __#{program}_handle_completion_types
                elif ! (( directive & 4 )); then
                    __#{program}_complete_files
                elif [[ -n ${BLE_ATTACHED-} ]]; then
                    # ble.sh would fall back to its own candidates.
                    compopt -o ble/no-default 2>/dev/null
                fi
            }

            __#{program}_get_completion_results() {
                out=$("${words[0]}" __complete "${words[@]:1:cword-1}" "$cur" 2>/dev/null) || return
                directive=${out##*$'\\n':}
                [[ $out == :* ]] && directive=${out#:}
                out=${out%$'\\n'*}
                [[ $out == :* ]] && out=""
                return 0
            }

            # As in cobra's script, out holds the lines as one string or as an array.
            __#{program}_handle_completion_types() {
                local chunk line
                local -a cands=() descs=()
                for chunk in "${out[@]}"; do
                    while IFS= read -r line; do
                        [[ -n $line ]] || continue
                        cands+=("${line%%$'\\t'*}")
                        if [[ $line == *$'\\t'* ]]; then descs+=("${line#*$'\\t'}"); else descs+=(""); fi
                    done <<<"$chunk"
                done
                # readline still breaks the word at "=", so "--flag=" must leave the replies.
                local prefix=""
                [[ $cur == -*=* && $COMP_WORDBREAKS == *=* ]] && prefix=${cur%%=*}=
                # Only a listing (the second TAB, show-all-if-ambiguous, show-all-if-unmodified)
                # shows descriptions, so what readline inserts is the bare value.
                local listing=""
                case ${COMP_TYPE-} in
                    33|63|64) (( ${#cands[@]} > 1 )) && listing=1 ;;
                esac
                local cand
                if [[ -z $listing ]]; then
                    for cand in "${cands[@]}"; do COMPREPLY+=("${cand#"$prefix"}"); done
                    return 0
                fi
                local i desc width=0 room
                for cand in "${cands[@]}"; do (( ${#cand} > width )) && width=${#cand}; done
                width=$(( width - ${#prefix} ))
                room=$(( ${COLUMNS:-80} - width - 4 ))
                for i in "${!cands[@]}"; do
                    cand=${cands[i]#"$prefix"} desc=${descs[i]}
                    if [[ -z $desc ]] || (( room < 8 )); then
                        COMPREPLY+=("$cand")
                        continue
                    fi
                    (( ${#desc} > room )) && desc="${desc:0:room-3}..."
                    printf -v line '%-*s  (%s)' "$width" "$cand" "$desc"
                    COMPREPLY+=("$line")
                done
            }

            # The file name is what follows "--flag=": the filedir helpers read cur.
            __#{program}_complete_files() {
                local i line prefix="" kind=-f readline=default
                local -a filedir=()
                (( directive & 16 )) && kind=-d readline=dirnames filedir=(-d)
                [[ $cur == -*=* ]] && prefix=${cur%%=*}=
                cur=${cur#"$prefix"}
                if declare -F _comp_compgen_filedir >/dev/null 2>&1; then
                    _comp_compgen_filedir "${filedir[@]}"
                elif declare -F _filedir >/dev/null 2>&1; then
                    _filedir "${filedir[@]}"
                elif ! compopt -o "$readline" 2>/dev/null; then
                    # Not mapfile: bash 3.2, macOS's /bin/bash, has neither it nor compopt.
                    while IFS= read -r line; do COMPREPLY+=("$line"); done < <(compgen "$kind" -- "$cur")
                fi
                if [[ -n $prefix && $COMP_WORDBREAKS != *=* ]]; then
                    for i in "${!COMPREPLY[@]}"; do COMPREPLY[i]=$prefix${COMPREPLY[i]}; done
                fi
            }

            complete -F __start_#{program} #{program}
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
                if (( ret )) && (( directive & 16 )); then
                    _files -/ && ret=0
                elif (( ret )) && ! (( directive & 4 )); then
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
                set -l complete __fish_complete_path
                if test (math "bitand($__#{program}_directive, 16)") -ne 0
                    set complete __fish_complete_directories
                end
                set -l token (commandline -ct)
                if string match -qr -- '^-[^=]*=' $token
                    set -l flag (string replace -r -- '=.*' '=' $token)
                    $complete (string replace -r -- '^[^=]*=' '' $token) | string replace -r -- '^' $flag
                else
                    $complete $token
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
