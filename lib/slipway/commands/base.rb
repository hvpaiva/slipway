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
        batch.warnings.each { Output.warning(context, it) }
        batch.inspections
      end

      # Shared by the verbs that print one line per resource, so the name is neutralized whichever
      # of them prints it.
      def self.result_text(context, kind, name, verb_word, role, reason: nil, dry_run: false)
        line = "#{kind.singular}/#{Output.plain(name)} #{context.paint(role, verb_word)}"
        line = "#{line} (#{reason})" if reason
        dry_run ? "#{line} #{context.paint(:dry_run, '(dry run)')}" : line
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
        context.puts(Base.result_text(context, kind, name, verb_word, role, dry_run:))
      end
    end
  end
end
