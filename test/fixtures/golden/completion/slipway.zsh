#compdef slipway
# zsh completion for slipway. Install it as _slipway in a directory on your fpath,
# such as ~/.zfunc/_slipway with `fpath+=~/.zfunc` before compinit, or load it
# with: source <(slipway completion zsh)
compdef _slipway slipway

_slipway() {
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
        if [[ $line == *$'\t'* ]]; then
            candidates+=("${${line%%$'\t'*}//:/\\:}:${line#*$'\t'}")
        else
            candidates+=("${line//:/\\:}")
        fi
    done
    (( directive & 2 )) && describe_opts+=(-S '')
    if (( ${#candidates} )); then
        _describe -t values 'slipway' candidates "${describe_opts[@]}" && ret=0
    fi
    if (( ret )) && ! (( directive & 4 )); then
        _files && ret=0
    fi
    return ret
}

if [[ "$funcstack[1]" == "_slipway" ]]; then
    _slipway "$@"
fi
