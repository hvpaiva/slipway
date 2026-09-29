# frozen_string_literal: true

require_relative 'cli/errors'

module Slipway
  # Label keys and values as Kubernetes defines them.
  module Labels
    # Callers decide whether the label came from the command line or a file.
    class Invalid < Error; end

    NAME = /\A[A-Za-z0-9]([-A-Za-z0-9_.]*[A-Za-z0-9])?\z/
    PREFIX = /\A[a-z0-9]([-a-z0-9]*[a-z0-9])?(\.[a-z0-9]([-a-z0-9]*[a-z0-9])?)*\z/
    MAX_NAME = 63
    MAX_PREFIX = 253
    KEY_RULE = 'letters, digits, dashes, underscores and dots, starting and ending with a letter or digit, ' \
               'at most 63 characters, with an optional DNS subdomain prefix and a slash'
    VALUE_RULE = 'empty, or letters, digits, dashes, underscores and dots, starting and ending with a letter ' \
                 'or digit, at most 63 characters'

    def self.valid_key?(key)
      return false unless key.is_a?(String)

      case key.split('/', -1)
      in [name] then valid_name?(name)
      in [prefix, name] then valid_prefix?(prefix) && valid_name?(name)
      else false
      end
    end

    def self.valid_value?(value) = value.is_a?(String) && (value.empty? || valid_name?(value))

    def self.validate_key!(key)
      return key if valid_key?(key)

      raise Invalid, "#{key.inspect} is not a valid label key: #{KEY_RULE}"
    end

    def self.validate_value!(value)
      return value if valid_value?(value)

      raise Invalid, "#{value.inspect} is not a valid label value: #{VALUE_RULE}"
    end

    def self.validate!(labels)
      labels.each do |key, value|
        validate_key!(key)
        validate_value!(value)
      end
    end

    def self.parse_pairs(words)
      words.each_with_object({}) do |word, pairs|
        key, value = split_pair(word, 'KEY=VALUE')
        duplicate!(key) if pairs.key?(key)
        pairs[key] = value
      end
    end

    # KEY=VALUE sets a label and KEY- removes one; returns [sets, removals].
    def self.parse_changes(words)
      sets = {}
      removals = []
      words.each do |word|
        if removal?(word)
          removals << removal_key(word, removals)
        else
          key, value = split_pair(word, 'KEY=VALUE or KEY-')
          duplicate!(key) if sets.key?(key)
          sets[key] = value
        end
      end
      reject_overlap(sets, removals)
    end

    # The form kubectl prints labels in.
    def self.format(labels)
      return nil if labels.empty?

      labels.sort.map { |key, value| "#{key}=#{value}" }.join(',')
    end

    def self.valid_name?(name) = name.length <= MAX_NAME && NAME.match?(name)

    def self.valid_prefix?(prefix) = prefix.length <= MAX_PREFIX && PREFIX.match?(prefix)

    def self.split_pair(word, expected)
      key, value = word.split('=', 2)
      raise CLI::UsageError, "invalid label #{word.inspect}: expected #{expected}" if value.nil?

      as_usage_error do
        validate_key!(key)
        validate_value!(value)
      end
      [key, value]
    end

    def self.removal?(word) = word.end_with?('-') && !word.include?('=')

    def self.removal_key(word, removals)
      key = as_usage_error { validate_key!(word.delete_suffix('-')) }
      duplicate!(key) if removals.include?(key)
      key
    end

    def self.duplicate!(key)
      raise CLI::UsageError, "label #{key.inspect} is given more than once"
    end

    def self.reject_overlap(sets, removals)
      overlap = sets.keys & removals
      return [sets, removals] if overlap.empty?

      raise CLI::UsageError, "label #{overlap.first.inspect} cannot be both set and removed"
    end

    # Label words come from the command line, so a bad key or value is a usage error there.
    def self.as_usage_error
      yield
    rescue Invalid => e
      raise CLI::UsageError, e.message
    end

    private_class_method :valid_name?, :valid_prefix?, :split_pair, :removal?, :removal_key, :duplicate!,
                         :reject_overlap, :as_usage_error
  end
end
