# frozen_string_literal: true

require_relative '../cli'
require_relative '../resources'
require_relative '../output'
require_relative 'options'
require_relative 'scope'

module Slipway
  module Commands
    # Subclasses define `self.command(factory)`, the registry entry whose handler is an
    # instance, and `run(runtime, context, args, opts)`, which raises Slipway::Error to fail.
    class Base
      # Prints the warnings here so neither read verb can forget them.
      def self.examine(runtime, context, resources)
        batch = runtime.inspector.examine_all(resources)
        batch.warnings.each { context.warn("#{context.paint_err(:warning, 'warning:')} #{it}") }
        batch.inspections
      end

      def initialize(factory)
        @factory = factory
      end

      def call(context, args, opts)
        runtime = @factory.call(context, opts)
        run(runtime, context, args, opts)
      end

      private

      def scope(runtime, context, opts) = Scope.new(runtime, context, opts)

      def result_line(context, kind, name, verb_word, role, dry_run: false)
        line = "#{kind.singular}/#{name} #{context.paint(role, verb_word)}"
        line = "#{line} #{context.paint(:dry_run, '(dry run)')}" if dry_run
        context.puts(line)
      end
    end
  end
end
