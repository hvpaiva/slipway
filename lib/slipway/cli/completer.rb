# frozen_string_literal: true

module Slipway
  module CLI
    # Speaks cobra's __complete protocol: one candidate per line, as `value` or
    # `value<TAB>description`, then a final `:N` line where N is 4 (no file completion) or 0
    # (let the shell complete file names).
    #
    # A completer proc on an Option or Positional may return an Array of values, a Hash of
    # value to description, or FILES to request file completion. Never raises: on any error
    # only `:4` is printed.
    class Completer
      FILES = :files
      NO_FILES_DIRECTIVE = 4
      FILES_DIRECTIVE = 0
      # bash splits `--flag=value` at the `=` (COMP_WORDBREAKS), so the separator may arrive
      # as a word of its own between the flag and its value.
      EQUALS = '='
      INLINE_VALUE = /\A--[^=]+=/

      def initialize(registry)
        @registry = registry
      end

      def call(context, words, _opts)
        candidates, directive = safely { complete(words) }
        candidates.each { |value, description| context.puts(description ? "#{value}\t#{description}" : value) }
        context.puts(":#{directive}")
      end

      def complete(words)
        words = words.dup
        current = words.pop || ''
        state = replay(words)
        return [[], NO_FILES_DIRECTIVE] unless state

        candidates = candidates_for(state, current)
        return [[], FILES_DIRECTIVE] if candidates == FILES

        [select(candidates, prefix(state, current), state.args), NO_FILES_DIRECTIVE]
      end

      private

      # `pending` is an option still waiting for its value; `literal` is set once `--` is seen.
      State = Struct.new(:command, :args, :pending, :literal)
      private_constant :State

      def safely
        yield
      rescue StandardError
        [[], NO_FILES_DIRECTIVE]
      end

      def replay(words)
        words.reduce(State.new(@registry.root, [], nil, false)) { |state, word| consume(state, word) or return nil }
      end

      def consume(state, word)
        if state.pending then consume_value(state, word)
        elsif word == '--' && !state.literal then state.literal = true
        elsif option_word?(word, state) then state.pending = pending_option(word, state)
        elsif state.command.group? then state.command = state.command.find(word) or return nil
        else state.args << word
        end
        state
      end

      # A lone `=` keeps the option open so the next word is still its value.
      def consume_value(state, word)
        state.pending = nil unless word == EQUALS
      end

      def option_word?(word, state) = word.start_with?('-') && !state.literal

      # An optional-argument option only takes its value attached, so it never waits.
      def pending_option(word, state)
        name = option_name(word)
        return nil unless name

        option = option_for(state.command, name)
        option unless option.nil? || option.flag? || option.optional
      end

      # nil when the value is attached: `--x=v`, `-ov`.
      def option_name(word)
        case word
        when INLINE_VALUE then nil
        when /\A--(.+)\z/, /\A-(.)\z/ then Regexp.last_match(1)
        end
      end

      def option_for(command, name)
        options_of(command).find { it.long == name || it.short == name }
      end

      def options_of(command) = @registry.globals + command.options

      def candidates_for(state, current)
        return values_of(state.pending, state.args) if state.pending
        return inline_value_candidates(state, current) if current.match?(INLINE_VALUE)
        return switch_candidates(state.command) if option_word?(current, state)
        return subcommand_candidates(state.command) if state.command.group?

        values_of(state.command.positional_at(state.args.size), state.args)
      end

      def values_of(target, args)
        values = target&.candidates(args) || []
        return values if values == FILES

        values.is_a?(Hash) ? values.to_a : values.map { [it, nil] }
      end

      # Values for `--flag=partial` carry the `--flag=` prefix so they replace the whole word.
      def inline_value_candidates(state, current)
        flag, = current.split(EQUALS, 2)
        values = values_of(option_for(state.command, flag.delete_prefix('--')), state.args)
        return values if values == FILES

        values.map { |value, description| ["#{flag}=#{value}", description] }
      end

      def switch_candidates(command)
        options_of(command).flat_map { |option| option.switches.map { [it, option.description] } }
      end

      def subcommand_candidates(command)
        command.visible_subcommands.map { [it.name, it.summary] }
      end

      def prefix(state, current)
        state.pending && current == EQUALS ? '' : current
      end

      def select(candidates, prefix, given)
        candidates.select { |value, _| value.start_with?(prefix) && !given.include?(value) }
      end
    end
  end
end
