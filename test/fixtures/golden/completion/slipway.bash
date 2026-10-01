# bash completion for slipway                             -*- shell-script -*-
# Install to ${XDG_DATA_HOME:-~/.local/share}/bash-completion/completions/slipway
# or load it with: eval "$(slipway completion bash)"
__start_slipway() {
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
    __slipway_get_completion_results || return
    (( directive & 2 )) && compopt -o nospace 2>/dev/null
    COMPREPLY=()
    if [[ -n $out ]]; then
        __slipway_handle_completion_types
    elif ! (( directive & 4 )); then
        __slipway_complete_files
    elif [[ -n ${BLE_ATTACHED-} ]]; then
        # ble.sh would fall back to its own candidates.
        compopt -o ble/no-default 2>/dev/null
    fi
}

__slipway_get_completion_results() {
    out=$("${words[0]}" __complete "${words[@]:1:cword-1}" "$cur" 2>/dev/null) || return
    directive=${out##*$'\n':}
    [[ $out == :* ]] && directive=${out#:}
    out=${out%$'\n'*}
    [[ $out == :* ]] && out=""
    return 0
}

# As in cobra's script, out holds the lines as one string or as an array.
__slipway_handle_completion_types() {
    local chunk line
    local -a cands=() descs=()
    for chunk in "${out[@]}"; do
        while IFS= read -r line; do
            [[ -n $line ]] || continue
            cands+=("${line%%$'\t'*}")
            if [[ $line == *$'\t'* ]]; then descs+=("${line#*$'\t'}"); else descs+=(""); fi
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
__slipway_complete_files() {
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

complete -F __start_slipway slipway
