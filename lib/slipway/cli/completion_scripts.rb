# frozen_string_literal: true

module Slipway
  module CLI
    # Shell wrappers that delegate every completion request to `PROGRAM __complete WORDS...`,
    # so the shell scripts never need regenerating when commands change.
    module CompletionScripts
      SHELLS = %w[bash zsh fish].freeze

      def self.render(shell, program)
        public_send(shell, program)
      end

      def self.bash(program)
        <<~BASH
          # bash completion for #{program}. Source it or install it to
          # ${XDG_DATA_HOME:-~/.local/share}/bash-completion/completions/#{program}
          _#{program}_complete() {
              local IFS=$'\\n'
              local words=("${COMP_WORDS[@]:1:COMP_CWORD}")
              COMPREPLY=($(#{program} __complete "${words[@]}" 2>/dev/null))
          }
          complete -o default -F _#{program}_complete #{program}
        BASH
      end

      def self.zsh(program)
        <<~ZSH
          #compdef #{program}
          # zsh completion for #{program}. Install it as _#{program} on your $fpath.
          _#{program}() {
              local -a candidates
              candidates=("${(@f)$(#{program} __complete "${words[@]:1:CURRENT-1}" 2>/dev/null)}")
              compadd -a candidates
          }
          compdef _#{program} #{program}
        ZSH
      end

      def self.fish(program)
        <<~FISH
          # fish completion for #{program}. Install it to ~/.config/fish/completions/#{program}.fish
          function __#{program}_complete
              set -l words (commandline -opc)
              set -e words[1]
              #{program} __complete $words (commandline -ct) 2>/dev/null
          end
          complete -c #{program} -f -a '(__#{program}_complete)'
        FISH
      end
    end
  end
end
