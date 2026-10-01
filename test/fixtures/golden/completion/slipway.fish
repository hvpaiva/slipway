# fish completion for slipway. Install it to ~/.config/fish/completions/slipway.fish
function __slipway_complete
    set -l line (commandline -cp)
    if set -q __slipway_line; and test "$__slipway_line" = "$line"
        return 0
    end
    set -g __slipway_line $line
    set -g __slipway_directive 4
    set -g __slipway_results
    set -l tokens (commandline -opc)
    set -l program $tokens[1]
    set -e tokens[1]
    set -l lines ($program __complete $tokens (commandline -ct) 2>/dev/null)
    or return 0
    if test (count $lines) -gt 0
        set -g __slipway_directive (string replace -r '^:' '' -- $lines[-1])
        set -e lines[-1]
        set -g __slipway_results $lines
    end
    if test (count $__slipway_results) -eq 1; and test (math "bitand($__slipway_directive, 2)") -ne 0
        set -l value (string split -m 1 \t -- $__slipway_results[1])[1]
        if not string match -qr '[@=/:.,]$' -- $value
            set -g __slipway_results $value $value.
        end
    end
end

function __slipway_wants_files
    __slipway_complete
    test (count $__slipway_results) -eq 0
    and test (math "bitand($__slipway_directive, 4)") -eq 0
end

# fish replaces the whole token, so a --flag= value has its path completed and the flag
# put back in front of each one.
function __slipway_complete_path
    set -l complete __fish_complete_path
    if test (math "bitand($__slipway_directive, 16)") -ne 0
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

complete -c slipway -e
complete -c slipway -n '__slipway_complete' -f -a '$__slipway_results'
complete -c slipway -n '__slipway_wants_files' -a '(__slipway_complete_path)'
