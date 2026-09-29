# frozen_string_literal: true

require_relative 'base'
require_relative '../editor'
require_relative '../manifest'
require_relative '../store'

module Slipway
  module Commands
    # `slipway edit TYPE NAME`: opens the manifest in the user's editor and saves what comes
    # back, reopening it with the failures as comments until it is valid, unchanged or blank.
    class Edit < Base
      DESCRIPTION = "Edit a resource from the default editor.\n\n" \
                    'The edit command allows you to directly edit any resource in the registry. It will open ' \
                    'the editor named by the SLIPWAY_EDITOR environment variable, then the editor key of the ' \
                    "configuration file, then VISUAL or EDITOR, or fall back to 'vi'.\n\n" \
                    'The kind, name and group of a resource cannot be changed. If an error occurs while saving, ' \
                    'the file is reopened with the relevant failures as comments at the top; saving it again ' \
                    'without changes cancels the edit.'
      HEADER = <<~TEXT
        # Please edit the object below. Lines beginning with a '#' will be ignored,
        # and an empty file will abort the edit. If an error occurs while saving this
        # file will be reopened with the relevant failures.
        #
      TEXT
      UNCHANGED = 'Edit cancelled, no changes made.'
      ABORTED = 'Edit cancelled, no valid changes were saved.'
      IMMUTABLE = 'kind, metadata.name and metadata.group cannot be changed'
      SOURCE = 'edited manifest'
      COMMENT = /\A\s*#/

      # Raised when the saved file is blank, or when a file reopened with failures is saved
      # as it was; exits with status 1.
      class Aborted < Slipway::Error; end

      def self.command(factory)
        CLI::Command.new(
          name: 'edit', summary: 'Edit a resource from the default editor', section: 'Basic Commands',
          description: DESCRIPTION, examples:,
          positionals: [Options::TYPE, Options.name_positional(factory, variadic: false, required: true)],
          handler: new(factory)
        )
      end

      def self.examples
        [
          CLI::Example.new(comment: "Edit the project named 'hldr'", command: 'edit project hldr'),
          CLI::Example.new(comment: 'Edit a project in the work group', command: 'edit project job -n work'),
          CLI::Example.new(comment: "Edit the group named 'work'", command: 'edit group work')
        ]
      end

      def run(runtime, context, args, opts)
        type, name = args
        scope = scope(runtime, opts)
        kind = scope.kind(type)
        resource = runtime.store.find(kind, name, group: scope.group)
        editor = Editor.new(env: context.env, preferred: runtime.config.editor)
        edited = Session.new(editor, kind, resource).edit
        return context.warn(UNCHANGED) if edited.nil?

        finish(runtime, context, kind, resource, edited)
      end

      private

      # kubectl reports `skipped` when the text changed but the object did not.
      def finish(runtime, context, kind, original, edited)
        return result_line(context, kind, original.name, 'skipped', :apply_unchanged) if edited == original

        runtime.store.save(edited)
        result_line(context, kind, original.name, 'edited', :apply_configured)
      end

      # One edit of one resource: the reopen loop and the checks between the editor's runs.
      # +edit+ returns the resource to save, or nil when the text came back unchanged.
      class Session
        def initialize(editor, kind, resource)
          @editor = editor
          @kind = kind
          @resource = resource
          @original = Manifest.dump(resource)
        end

        def edit
          text = @original
          problem = nil
          loop do
            edited = strip(@editor.edit(buffer(text, problem), filename: "#{@resource.name}.yaml"))
            raise Aborted, ABORTED if edited.strip.empty? || (problem && edited == text)
            return nil if edited == @original

            return parse(edited)
          rescue Manifest::Invalid => e
            problem = e.message
            text = edited
          end
        end

        private

        # The header, the previous failure as a comment block, then the text to edit.
        def buffer(text, problem)
          return "#{HEADER}#{text}" if problem.nil?

          "#{HEADER}#{problem.lines.map { "# #{it.chomp}\n" }.join}#\n#{text}"
        end

        def strip(text) = text.lines.grep_v(COMMENT).join

        def parse(text)
          parsed = Manifest.parse_yaml(text, source: SOURCE, default_group: group)
          raise Manifest::Invalid.new(SOURCE, IMMUTABLE) unless same_identity?(parsed)

          parsed.created_at ? parsed : parsed.with(created_at: @resource.created_at)
        end

        def group = @kind.namespaced? ? @resource.group : Store::DEFAULT_GROUP

        def same_identity?(parsed)
          parsed.instance_of?(@kind.klass) && parsed.name == @resource.name &&
            (!@kind.namespaced? || parsed.group == @resource.group)
        end
      end

      private_constant :Session
    end
  end
end
