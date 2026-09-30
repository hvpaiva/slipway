# frozen_string_literal: true

module Slipway
  module CLI
    # Speaks cobra's __complete protocol: one candidate per line, as `value` or
    # `value<TAB>description`, then a final `:N` line. N is a sum of cobra's directives: 4 when
    # the shell must not complete file names in place of the candidates, 2 when it must not add a
    # space after the one it inserts, and 0 lets the shell complete file names.
    #
    # A completer proc on an Option or Positional receives the positional words typed so far and
    # the word being completed, without a `--flag=` in front of it, and may return an Array of
    # values, a Hash of value to description, either of them wrapped in NoSpace, or FILES to
    # request file completion. The candidates are filtered by that word afterwards. Never raises:
    # on any error only `:4` is printed.
    class Completer
      FILES = :files
      FILES_DIRECTIVE = 0
      NO_SPACE_DIRECTIVE = 2
      NO_FILES_DIRECTIVE = 4
      # Candidates the user goes on typing after, such as a field path that continues after a
      # dot: the shell adds no space after the one it inserts. The directive covers the whole
      # answer, so a completer returns NoSpace only when a candidate that matches the word goes
      # on, and a finished value still gets its space.
      NoSpace = Data.define(:candidates)
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

        case candidates_for(state, current)
        in FILES then [[], FILES_DIRECTIVE]
        in NoSpace(candidates:) then [select(candidates, state, current), NO_FILES_DIRECTIVE | NO_SPACE_DIRECTIVE]
        in candidates then [select(candidates, state, current), NO_FILES_DIRECTIVE]
        end
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
        return values_of(state.pending, state.args, prefix(state, current)) if state.pending
        return inline_value_candidates(state, current) if current.match?(INLINE_VALUE)
        return switch_candidates(state.command) if option_word?(current, state)
        return subcommand_candidates(state.command) if state.command.group?

        values_of(state.command.positional_at(state.args.size), state.args, current)
      end

      def values_of(target, args, current)
        within(target&.candidates(args, current) || []) do |values|
          values.is_a?(Hash) ? values.to_a : values.map { [it, nil] }
        end
      end

      # Values for `--flag=partial` carry the `--flag=` prefix so they replace the whole word.
      def inline_value_candidates(state, current)
        flag, typed = current.split(EQUALS, 2)
        values = values_of(option_for(state.command, flag.delete_prefix('--')), state.args, typed)
        within(values) { |pairs| pairs.map { |value, description| ["#{flag}=#{value}", description] } }
      end

      # Yields the candidates, unwrapped from a NoSpace and wrapped back; FILES passes through.
      def within(values)
        case values
        in FILES then FILES
        in NoSpace(candidates:) then NoSpace.new(yield(candidates))
        else yield(values)
        end
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

      def select(candidates, state, current)
        typed = prefix(state, current)
        candidates.select { |value, _| value.start_with?(typed) && !state.args.include?(value) }
      end
    end
  end
end
