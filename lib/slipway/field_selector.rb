# frozen_string_literal: true

require_relative 'cli/errors'

module Slipway
  # A kubectl field selector, matched against the object json and yaml print. +fields+ maps
  # each path a resource supports to the value the path compares as when the object leaves
  # it out.
  class FieldSelector
    Requirement = Data.define(:path, :operator, :value, :absent) do
      def match?(object)
        found = object.dig(*path.split('.'))
        equal = (found.nil? ? absent : found.to_s) == value
        operator == :equals ? equal : !equal
      end
    end

    class Parser
      # A backslash escapes the character after it, so an escaped comma stays in its term.
      TERM = /(?:\\.|[^\\,])*\\?/m
      # As in kubectl, the leftmost operator splits the term, and at one position != and ==
      # win over =.
      OPERATOR = /\A(.*?)(!=|==|=)(.*)\z/m
      OPERATORS = { '=' => :equals, '==' => :equals, '!=' => :not_equals }.freeze
      ESCAPE = /\\(.?)|=/m
      # The three characters kubectl escapes in a value; any other escape is refused.
      ESCAPABLE = ['\\', ',', '='].freeze

      # Under the C locale ARGV arrives as BINARY, and a BINARY value holding non-ASCII bytes
      # never equals the UTF-8 string git or the manifest gave, so the bytes are read as UTF-8.
      def initialize(expression, fields)
        @expression = String.new(expression.to_s, encoding: Encoding::UTF_8)
        @fields = fields
      end

      # kubectl skips empty terms, so a trailing comma is not an error.
      def parse
        fail!('invalid UTF-8') unless @expression.valid_encoding?

        @expression.strip.scan(TERM).reject(&:empty?).map { requirement(it) }
      end

      private

      def requirement(term)
        match = OPERATOR.match(term)
        fail!("can't understand #{term.inspect}") if match.nil?
        path, operator, value = match.captures
        fail!("field label not supported: #{path.inspect}") unless @fields.key?(path)

        Requirement.new(path:, operator: OPERATORS.fetch(operator), value: unescape(value), absent: @fields.fetch(path))
      end

      def unescape(value)
        value.gsub(ESCAPE) do |found|
          escaped = Regexp.last_match(1)
          next escaped if ESCAPABLE.include?(escaped)

          fail!(escaped.nil? ? "unescaped character in value: #{found}" : "invalid escape sequence: #{found}")
        end
      end

      def fail!(reason)
        raise CLI::UsageError, "invalid field selector #{@expression.inspect}: #{reason}"
      end
    end

    # nil or a blank string selects everything.
    def self.parse(expression, fields:) = new(Parser.new(expression, fields).parse)

    def initialize(requirements)
      @requirements = requirements.freeze
    end

    def empty? = @requirements.empty?

    def match?(object) = @requirements.all? { it.match?(object) }

    # The block turns an item into the object its fields are read from.
    def filter(items)
      return items if empty?

      items.select { match?(yield(it)) }
    end
  end
end
