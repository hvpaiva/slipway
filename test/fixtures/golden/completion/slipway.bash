# bash completion for slipway                             -*- shell-script -*-
# Install to ${XDG_DATA_HOME:-~/.local/share}/bash-completion/completions/slipway
# or load it with: eval "$(slipway completion bash)"
_slipway() {
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
    directive=${out##*$'\n':}
    [[ $out == :* ]] && directive=${out#:}
    out=${out%$'\n'*}
    [[ $out == :* ]] && out=""

    COMPREPLY=()
    local line
    if [[ -n $out ]]; then
        while IFS= read -r line; do COMPREPLY+=("${line%%$'\t'*}"); done <<<"$out"
    fi
    # readline still breaks the word at "=", so "--flag=" must leave the replies.
    if [[ $cur == -*=* && $COMP_WORDBREAKS == *=* ]]; then
        local i prefix=${cur%%=*}=
        for i in "${!COMPREPLY[@]}"; do COMPREPLY[i]=${COMPREPLY[i]#"$prefix"}; done
    fi
    (( directive & 2 )) && compopt -o nospace 2>/dev/null
    if (( ${#COMPREPLY[@]} == 0 )) && ! (( directive & 4 )); then
        if declare -F _comp_compgen_filedir >/dev/null 2>&1; then
            _comp_compgen_filedir
        elif declare -F _filedir >/dev/null 2>&1; then
            _filedir
        elif ! compopt -o default 2>/dev/null; then
            mapfile -t COMPREPLY < <(compgen -f -- "$cur")
        fi
    fi
}
complete -F _slipway slipway
