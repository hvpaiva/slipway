# frozen_string_literal: true

require 'test_helper'

# ble.sh patches a bash completion shaped like cobra's (patch:cobraV2 in its core-complete.sh):
# it runs words[0] through its own function, takes the lines with a description for its menu and
# hands the others back in out. Without __PROGRAM_extract_activeHelp it hands them back as out,
# not as completions. ble.sh does not run in CI, so BLE_ANSWER does the same in plain bash.
class CompletionBleTest < Minitest::Test
  include ShellHarness

  BLE_ANSWER = <<~'BASH'
    source "$1/slipway.bash"
    BLE_ATTACHED=1 COMP_TYPE=9
    marker=$1/invoked asked=() yielded=()
    compopt() { asked+=("$*"); }
    invoke() { : >"$marker"; "${orig_words[0]}" "$@"; }

    eval "ble_original_$(declare -f __slipway_get_completion_results)"
    __slipway_get_completion_results() {
        local -a orig_words=("${words[@]}")
        local -a words=(invoke "${orig_words[@]:1}")
        ble_original___slipway_get_completion_results
    }
    eval "ble_original_$(declare -f __slipway_handle_completion_types)"
    __slipway_handle_completion_types() {
        local lines line unprocessed=()
        for lines in "${out[@]}"; do
            while IFS= read -r line; do
                if [[ $line == *$'\t'* ]]; then
                    [[ ${line%%$'\t'*} == "$cur"* ]] && yielded+=("${line%%$'\t'*}")
                elif [[ -n $line ]]; then
                    unprocessed+=("$line")
                fi
            done <<<"$lines"
        done
        if (( ${#unprocessed[@]} )); then
            out=("${unprocessed[@]}")
            ble_original___slipway_handle_completion_types
        fi
    }

    read -ra COMP_WORDS <<<"$2"
    [[ $2 == *" " ]] && COMP_WORDS+=("")
    COMP_CWORD=$(( ${#COMP_WORDS[@]} - 1 ))
    COMP_LINE=$2 COMP_POINT=${#2}
    __start_slipway "${COMP_WORDS[0]}" "${COMP_WORDS[COMP_CWORD]}" "${COMP_WORDS[COMP_CWORD-1]}"
    if [[ -e $marker ]]; then echo invoked; else echo direct; fi
    for line in "${yielded[@]}"; do printf '%s\n' "$line"; done
    echo --
    for line in "${COMPREPLY[@]}"; do printf '%s\n' "$line"; done
    echo --
    for line in "${asked[@]}"; do printf '%s\n' "$line"; done
  BASH

  def test_the_script_has_the_shape_ble_sh_patches
    script = Slipway::CLI::CompletionScripts.render('bash', 'slipway')

    assert_includes script, 'complete -F __start_slipway slipway'
    assert_includes script, '__slipway_get_completion_results() {'
    assert_includes script, '__slipway_handle_completion_types() {'
    refute_includes script, '_extract_activeHelp'
  end

  def test_ble_sh_runs_the_program_and_lists_the_described_candidates_itself
    with_completion_stub do |dir, env|
      assert_equal ['invoked', %w[get create explain config help version completion man], [], []],
                   ble_answer(dir, 'slipway ', env)
      assert_equal ['invoked', %w[explain], [], []], ble_answer(dir, 'slipway ex', env)
    end
  end

  def test_values_without_a_description_come_back_as_replies
    with_completion_stub do |dir, env|
      assert_equal ['invoked', [], %w[alpha beta], []], ble_answer(dir, 'slipway get projects ', env)
      assert_equal ['invoked', [], %w[json], []], ble_answer(dir, 'slipway get projects --output=j', env)
    end
  end

  def test_an_empty_answer_without_files_turns_off_the_ble_sh_fallback
    with_completion_stub do |dir, env|
      assert_equal ['invoked', [], [], ['-o ble/no-default']], ble_answer(dir, 'slipway config bogus ', env)
    end
  end

  private

  # How the program was reached, the candidates ble.sh took, the replies, and the compopt calls.
  def ble_answer(dir, line, env)
    lines = run_shell(env, 'bash', '--norc', '--noprofile', '-c', BLE_ANSWER, 'harness', dir, line)
    reached, *rest = lines
    [reached, *['--', *rest].slice_before('--').map { it.drop(1) }]
  end
end
