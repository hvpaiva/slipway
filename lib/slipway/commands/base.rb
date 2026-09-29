# frozen_string_literal: true

require_relative '../cli'
require_relative '../resources'
require_relative '../output'
require_relative 'options'
require_relative 'scope'

module Slipway
  module Commands
    # A verb's handler: builds the runtime through the factory it was given and hands the
    # call to +run+. Every verb class defines `self.command(factory)`, the registry entry
    # whose handler is an instance, `self.examples` for that entry, and `run(runtime,
    # context, args, opts)`, which prints its result lines and raises Slipway::Error to fail.
    class Base
      # Examines +resources+ and prints one warning line per reason a project came back
      # Unknown, so neither read verb can forget the warnings; returns the inspections.
      def self.examine(runtime, context, resources)
        batch = runtime.inspector.examine_all(resources)
        batch.warnings.each { context.warn("#{context.paint_err(:warning, 'warning:')} #{it}") }
        batch.inspections
      end

      def initialize(factory)
        @factory = factory
      end

      # The registry handler: builds the runtime for this call and runs the verb.
      def call(context, args, opts)
        runtime = @factory.call(context, opts)
        run(runtime, context, args, opts)
      end

      private

      def scope(runtime, context, opts) = Scope.new(runtime, context, opts)

      # Prints kubectl's result line, `project/hldr created`, with the verb painted in +role+
      # and ` (dry run)` appended when nothing was written.
      def result_line(context, kind, name, verb_word, role, dry_run: false)
        line = "#{kind.singular}/#{name} #{context.paint(role, verb_word)}"
        line = "#{line} #{context.paint(:dry_run, '(dry run)')}" if dry_run
        context.puts(line)
      end
    end
  end
end
