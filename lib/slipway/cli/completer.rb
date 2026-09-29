# frozen_string_literal: true

module Slipway
  module CLI
    # Backs the hidden `__complete WORDS...` command: replays the words typed so far
    # against the registry and prints candidates for the last one. Never fails.
    class Completer
      def initialize(registry)
        @registry = registry
      end

      def call(context, words, _opts = {})
        candidates(words).each { context.puts(it) }
      rescue StandardError
        nil
      end

      def candidates(words)
        words = words.dup
        current = words.pop || ''
        state = replay(words)
        return [] unless state

        select(candidates_for(state, current), current, state.args)
      end

      private

      State = Struct.new(:command, :args, :pending, :literal)

      # Returns nil when the words name a subcommand that does not exist.
      def replay(words)
        words.reduce(State.new(@registry.root, [], nil, false)) { |state, word| consume(state, word) or return nil }
      end

      def consume(state, word)
        if state.pending then state.pending = nil
        elsif word == '--' && !state.literal then state.literal = true
        elsif option_word?(word, state) then state.pending = pending_option(word, state)
        elsif state.command.group? then state.command = state.command.find(word) or return nil
        else state.args << word
        end
        state
      end

      def option_word?(word, state) = word.start_with?('-') && !state.literal

      # Returns the Option still waiting for its value, or nil when the word carried one.
      def pending_option(word, state)
        name = option_name(word)
        return nil unless name

        option = option_for(state.command, name)
        option unless option.nil? || option.flag?
      end

      # The name a switch word refers to, or nil when the value is attached (`--x=v`, `-ov`).
      def option_name(word)
        case word
        when /\A--[^=]+=/ then nil
        when /\A--(.+)\z/, /\A-(.)\z/ then Regexp.last_match(1)
        end
      end

      def option_for(command, name)
        (@registry.globals + command.options).find { it.long == name || it.short == name }
      end

      def candidates_for(state, current)
        return state.pending.candidates(state.args) if state.pending
        return inline_value_candidates(state, current) if current.match?(/\A--[^=]+=/)
        return (@registry.globals + state.command.options).flat_map(&:switches) if option_word?(current, state)
        return state.command.visible_subcommands.flat_map(&:names) if state.command.group?

        positional_candidates(state)
      end

      def inline_value_candidates(state, current)
        option_for(state.command, current[/\A--([^=]+)=/, 1])&.candidates(state.args) || []
      end

      def positional_candidates(state)
        state.command.positional_at(state.args.size)&.candidates(state.args) || []
      end

      def select(candidates, current, given)
        prefix = current.sub(/\A--[^=]+=/, '')
        candidates.select { it.start_with?(prefix) } - given
      end
    end
  end
end
