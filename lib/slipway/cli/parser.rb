# frozen_string_literal: true

require 'optparse'

module Slipway
  module CLI
    # Builds an OptionParser from registry Options and writes parsed values into a Hash
    # keyed by Option#key. The global prefix and the command share one Hash.
    class Parser
      def initialize(options, values)
        @options = options
        @values = values
      end

      # Stops at the first non-option word: `slipway [GLOBALS] VERB ...`.
      def order!(argv) = parser.order!(argv)

      # Interleaves options and positionals: `slipway get projects -o json alpha`.
      def permute!(argv) = parser.permute!(argv)

      # Fills in registry defaults for options that were not given.
      def defaults
        @options.each { |opt| @values[opt.key] = opt.default unless @values.key?(opt.key) }
        @values
      end

      private

      def parser
        @parser ||= OptionParser.new do |o|
          o.require_exact = true
          drop_officious_completion(o)
          @options.each do |opt|
            o.on(*opt.switch_spec) { |raw| @values[opt.key] = opt.accept(@values[opt.key], raw) }
          end
        end
      end

      # OptionParser registers `--*-completion-bash=WORD` and `--*-completion-zsh` on every
      # parser; both print to $stdout and call `exit` mid-parse, which bypasses the Context
      # and the exit-code contract. `--help` and `--version` are shadowed by the registry's
      # own switches; these two have no registry counterpart, so they go.
      def drop_officious_completion(parser)
        parser.base.long.delete_if { |name, _| name.start_with?('*-') }
      end
    end
  end
end
