# frozen_string_literal: true

require_relative '../cli'
require_relative '../resources'
require_relative '../schema'
require_relative '../output'
require_relative 'options'

module Slipway
  module Commands
    # Reads only Schema, so it builds no runtime and answers even where the configuration file is
    # broken or git is missing.
    class Explain
      DESCRIPTION = "Describe fields and structure of the resource types.\n\n" \
                    'This command describes the fields of each resource type, as a manifest holds them. Fields ' \
                    'are identified by a dotted path after the type word, such as project.spec.syncPolicy. Each ' \
                    'field shows its type, -required- when a manifest must have it, and a description with the ' \
                    'rule its value follows and its default; --recursive prints the whole tree of names and ' \
                    "types instead.\n\n" \
                    "#{Options::TYPES_SENTENCE} Field names are case-sensitive, as in a manifest.".freeze
      USAGE = '<TYPE>[.FIELD]...'
      SEPARATOR = '.'
      RECURSIVE = CLI::Option.new(long: 'recursive', summary: 'Print the name of all the fields recursively',
                                  description: 'If present, print the name of all the fields recursively. ' \
                                               'Otherwise, print the available fields with their description.')

      def self.command(_factory)
        CLI::Command.new(
          name: 'explain', summary: 'Get documentation for a resource', section: 'Basic Commands',
          description: DESCRIPTION, examples:, usage: USAGE, options: [RECURSIVE], handler: new,
          positionals: [CLI::Positional.new(name: 'TYPE', completer: ->(_given, current) { paths(current) },
                                            description: 'The resource type, then the dotted path of a field, ' \
                                                         'such as project.spec.syncPolicy.')]
        )
      end

      def self.examples
        [
          CLI::Example.new(comment: 'Get the documentation of the resource and its fields',
                           command: 'explain projects'),
          CLI::Example.new(comment: 'Get all the fields in the resource', command: 'explain projects --recursive'),
          CLI::Example.new(comment: 'Get the documentation of a specific field of a resource',
                           command: 'explain project.spec.syncPolicy')
        ]
      end
      private_class_method :examples

      # The type words, then the fields one level under the path typed so far, as whole paths.
      # A path with fields under it goes on after a dot, so the shell adds no space after it. A
      # path naming no type or field has no candidates, never an error in the shell.
      def self.paths(current)
        parent, dot, = current.rpartition(SEPARATOR)
        offered = (dot.empty? ? types : children(parent)).select { |path, _, _| path.start_with?(current) }
        candidates = offered.to_h { |path, description, _| [path, description] }
        offered.any? { |_, _, continues| continues } ? CLI::Completer::NoSpace.new(candidates) : candidates
      rescue Slipway::Error
        []
      end

      def self.types = Options::TYPE_DESCRIPTIONS.map { |word, description| [word, description, true] }

      def self.children(path)
        _, field = lookup(path)
        field.fields.map { ["#{path}#{SEPARATOR}#{it.name}", "<#{it.type}>", !it.fields.empty?] }
      end

      # The kind the type word names and the field the path leads to; raises UsageError for a field
      # that does not exist, in kubectl's words.
      def self.lookup(path)
        # split turns an empty word into no words at all, not into one empty type word.
        type, *names = path.split(SEPARATOR, -1)
        kind = Resources.resolve(type || '')
        field = names.reduce(Schema::KINDS.fetch(kind.title)) do |parent, name|
          parent.field(name) || raise(CLI::UsageError, "field #{name.inspect} does not exist")
        end
        [kind, field]
      end
      private_class_method :types, :children

      def kinds = Resources::KINDS

      def call(context, args, opts)
        kind, field = Explain.lookup(args.fetch(0))
        Output::Explain.new(context).print(kind: kind.title, field: document(field),
                                           named: args.fetch(0).include?(SEPARATOR), recursive: opts[:recursive])
      end

      private

      def document(field)
        Output::Explain::Field.new(name: field.name, type: field.type, required: field.required,
                                   description: description(field), fields: field.fields.map { document(it) })
      end

      # The Kubernetes API reference words a default the same way: "Defaults to 1."
      def description(field) = field.default.nil? ? field.meaning : "#{field.meaning} Defaults to #{field.default}."
    end
  end
end
