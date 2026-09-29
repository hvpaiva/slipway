# frozen_string_literal: true

module Slipway
  module CLI
    class Validator
      def initialize(command, path, registry)
        @command = command
        @path = path
        @registry = registry
      end

      def call(args, opts)
        check_arity(args)
        check_positional_enums(args)
        check_required(opts)
        check_option_enums(opts)
      end

      private

      def check_arity(args)
        if args.size < @command.min_args
          missing = @command.positionals[args.size]
          usage_error("missing required argument #{missing.name.inspect}")
        end
        max = @command.max_args
        usage_error("unexpected argument #{args[max].inspect}") if max && args.size > max
      end

      def check_positional_enums(args)
        args.each_with_index do |arg, index|
          positional = @command.positional_at(index)
          next unless positional&.enum && !positional.enum.include?(arg)

          usage_error("invalid argument #{arg.inspect} for #{positional.name}: #{allowed(positional.enum)}")
        end
      end

      def check_required(opts)
        @command.options.select(&:required).each do |opt|
          usage_error("required flag(s) #{"--#{opt.long}".inspect} not set") if opts[opt.key].nil?
        end
      end

      def check_option_enums(opts)
        (@registry.globals + @command.options).select(&:enum).each do |opt|
          value = opts[opt.key]
          next if value.nil? || opt.enum.include?(value)

          usage_error("invalid argument #{value.inspect} for --#{opt.long}: #{allowed(opt.enum)}")
        end
      end

      def allowed(values) = "must be one of #{values.join(', ')}"

      def usage_error(message)
        raise UsageError.new(message, hint: @registry.help_hint(@path))
      end
    end
  end
end
