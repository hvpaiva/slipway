# frozen_string_literal: true

module Slipway
  module Output
    # A value whose color the caller has already chosen, such as a STATUS word.
    Painted = Data.define(:role, :text)

    class Describe
      NONE = '<none>'
      INDENT = '  '
      GAP = 2
      TIME_FORMAT = '%Y-%m-%dT%H:%M:%SZ'

      def initialize(context)
        @context = context
      end

      # A value that is a non-empty list of [key, value] pairs renders as a nested block; any
      # other list prints one item per line.
      def render(entries)
        return '' if entries.empty?

        "#{block(entries, 0).join("\n")}\n"
      end

      def print(entries) = @context.print(render(entries))

      private

      def block(entries, depth)
        width = entries.map { |key, _| key.to_s.size + 1 }.max + GAP
        entries.flat_map { |key, value| entry(key.to_s, value, depth, width) }
      end

      def entry(key, value, depth, width)
        indent = INDENT * depth
        label = "#{indent}#{@context.style.paint_cycle(:describe_keys, depth, key)}:"
        return [label, *block(value, depth + 1)] if section?(value)

        first, *rest = values(value)
        column = ' ' * (indent.size + width)
        [label + (' ' * (width - key.size - 1)) + first, *rest.map { column + it }]
      end

      def section?(value)
        value.is_a?(Array) && !value.empty? && value.all? { it.is_a?(Array) && it.size == 2 }
      end

      # Never empty: #entry puts the first line beside the key.
      def values(value)
        case value
        when nil, [], {} then [@context.paint(:none, NONE)]
        when Hash then value.sort.map { |key, item| Output.plain("#{key}=#{item}") }
        when Array then value.map { Output.plain(it) }
        else [scalar(value)]
        end
      end

      def scalar(value)
        case value
        when Painted then @context.paint(value.role, Output.plain(value.text))
        when Numeric then @context.paint(:number, value)
        when true then @context.paint(:boolean_true, value)
        when false then @context.paint(:boolean_false, value)
        when Time then value.utc.strftime(TIME_FORMAT)
        else Output.plain(value)
        end
      end
    end
  end
end
