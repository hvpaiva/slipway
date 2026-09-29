# frozen_string_literal: true

require_relative 'cli/errors'
require_relative 'labels'

module Slipway
  # A kubectl label selector: comma-separated requirements that all have to hold for a match.
  class Selector
    # One requirement. +values+ is sorted and holds one value for =, != and none for existence checks.
    Requirement = Data.define(:key, :operator, :values) do
      def match?(labels)
        case operator
        when :equals, :in then labels.key?(key) && values.include?(labels[key])
        when :not_equals, :not_in then !labels.key?(key) || !values.include?(labels[key])
        when :exists then labels.key?(key)
        when :does_not_exist then !labels.key?(key)
        end
      end

      def to_s
        case operator
        when :equals then "#{key}=#{values.first}"
        when :not_equals then "#{key}!=#{values.first}"
        when :in then "#{key} in (#{values.join(',')})"
        when :not_in then "#{key} notin (#{values.join(',')})"
        when :exists then key
        when :does_not_exist then "!#{key}"
        end
      end
    end

    # Recursive-descent parser over the token stream of one selector expression.
    class Parser
      TOKEN = /==|!=|[=!(),]|[^\s=!(),]+/
      SYMBOLS = %w[( ) , = == != !].freeze
      KEYWORDS = { 'in' => :in, 'notin' => :not_in }.freeze
      EXACT = { '=' => :equals, '==' => :equals, '!=' => :not_equals }.freeze

      def initialize(expression)
        @expression = expression
        @tokens = expression.scan(TOKEN)
        @position = 0
      end

      def parse
        return [] if @tokens.empty?

        requirements = [requirement]
        until peek.nil?
          expect(',', "expected ',' or the end of the selector")
          fail!("expected a requirement after ','") if peek.nil?
          requirements << requirement
        end
        requirements.sort_by { [it.key, it.to_s] }
      end

      private

      def requirement
        return build(key_after_bang, :does_not_exist, []) if peek == '!'

        key = key_token
        case peek
        when nil, ',' then build(key, :exists, [])
        when *EXACT.keys then build(key, EXACT.fetch(advance), [exact_value])
        when *KEYWORDS.keys then build(key, KEYWORDS.fetch(advance), set_values)
        else fail!("unexpected #{peek.inspect} after #{key.inspect}")
        end
      end

      def key_after_bang
        advance
        fail!("expected a key after '!'") unless identifier?(peek) && !KEYWORDS.key?(peek)
        advance
      end

      def key_token
        return advance if identifier?(peek) && !KEYWORDS.key?(peek)

        fail!(peek.nil? ? 'expected a key' : "expected a key, found #{peek.inspect}")
      end

      # kubectl reads +key=+ and +key=,other+ as a comparison with the empty value.
      def exact_value
        return '' if peek.nil? || peek == ','
        return advance if identifier?(peek)

        fail!("expected a value, found #{peek.inspect}")
      end

      # Every slot between the parentheses is a value; an empty slot, as in +()+ or +(a,)+, is the empty value.
      def set_values
        expect('(', "expected '(' after #{@tokens[@position - 1].inspect}")
        values = []
        loop do
          values << (identifier?(peek) ? advance : '')
          break if accept(')')

          expect(',', "expected ',' or ')' in the value set")
        end
        values.uniq.sort
      end

      def build(key, operator, values)
        fail!("invalid label key #{key.inspect}") unless Labels.valid_key?(key)
        values.each { fail!("invalid label value #{it.inspect}") unless Labels.valid_value?(it) }
        Requirement.new(key:, operator:, values:)
      end

      def identifier?(token) = !token.nil? && !SYMBOLS.include?(token)

      def peek = @tokens[@position]

      def advance
        token = peek
        @position += 1
        token
      end

      # Consumes +token+ when it is next, returning it; nil otherwise.
      def accept(token)
        return unless peek == token

        advance
      end

      def expect(token, reason)
        fail!(reason) unless accept(token)
      end

      def fail!(reason)
        raise CLI::UsageError, "invalid selector #{@expression.inspect}: #{reason}"
      end
    end

    attr_reader :requirements

    def self.parse(expression) = new(Parser.new(expression.to_s).parse)

    def initialize(requirements)
      @requirements = requirements.freeze
    end

    def match?(labels) = requirements.all? { it.match?(labels) }

    # A blank expression selects everything.
    def empty? = requirements.empty?

    # The normalized form: requirements sorted by key, values sorted, == written as =.
    def to_s = requirements.join(',')
  end
end
