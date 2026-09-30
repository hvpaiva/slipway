# frozen_string_literal: true

require_relative 'base'

module Slipway
  module Commands
    module RolloutCommand
      # Writes one spec field of each named project and prints what changed. No git command runs:
      # the next fetch or sync reads the field.
      class SpecChange < Base
        def run(runtime, context, args, opts)
          scope = scope(runtime, context, opts)
          names = scope.project_targets(args, verb: self.class::VERB)
          scope.select(Resources::PROJECTS, names) { |projects| projects.each { write(runtime, context, it) } }
        end

        private

        def write(runtime, context, project)
          changed = change(project)
          runtime.store.save(changed) if changed
          word, role = changed ? [self.class::DONE, :result_changed] : [self.class::NOTHING, :result_unchanged]
          result_line(context, Resources::PROJECTS, project.name, word, role)
        end
      end

      class Unpin < SpecChange
        DESCRIPTION = "Stop holding projects at a revision.\n\n" \
                      'Removes spec.revision from the manifest of each named project, so the next slipway sync ' \
                      'fast-forwards its branch onto its upstream again. The repository is left as it is. A ' \
                      'project without spec.revision prints not pinned.'
        VERB = 'unpin'
        DONE = 'unpinned'
        NOTHING = 'not pinned'

        def self.command(factory)
          CLI::Command.new(
            name: 'unpin', summary: 'Stop holding a project at a revision', description: DESCRIPTION,
            usage: MANY_USAGE,
            examples: [CLI::Example.new(comment: 'Let project hldr follow its upstream again',
                                        command: 'rollout unpin hldr')],
            positionals: [Options.project_positional(factory, required: true)], handler: new(factory)
          )
        end

        private

        def change(project) = project.revision && project.with(revision: nil)
      end

      class Pause < SpecChange
        DESCRIPTION = "Mark the provided projects as paused.\n\n" \
                      'Sets spec.paused in the manifest of each named project. Paused projects are left alone by ' \
                      'slipway fetch and slipway sync, which run no git command in them; slipway rollout undo still ' \
                      'acts on them. Use slipway rollout resume to resume a paused project.'
        VERB = 'pause'
        DONE = 'paused'
        NOTHING = 'already paused'

        def self.command(factory)
          CLI::Command.new(
            name: 'pause', summary: 'Mark the provided project as paused', description: DESCRIPTION,
            usage: MANY_USAGE,
            examples: [CLI::Example.new(comment: 'Keep fetch and sync away from project dots',
                                        command: 'rollout pause dots')],
            positionals: [Options.project_positional(factory, required: true)], handler: new(factory)
          )
        end

        private

        def change(project) = project.paused ? nil : project.with(paused: true)
      end

      class Resume < SpecChange
        DESCRIPTION = "Resume paused projects.\n\n" \
                      'Removes spec.paused from the manifest of each named project, so slipway fetch and slipway ' \
                      'sync act on it again. A project that is not paused prints not paused.'
        VERB = 'resume'
        DONE = 'resumed'
        NOTHING = 'not paused'

        def self.command(factory)
          CLI::Command.new(
            name: 'resume', summary: 'Resume a paused project', description: DESCRIPTION, usage: MANY_USAGE,
            examples: [CLI::Example.new(comment: 'Resume the paused project dots', command: 'rollout resume dots')],
            positionals: [Options.project_positional(factory, required: true)], handler: new(factory)
          )
        end

        private

        def change(project) = project.paused ? project.with(paused: false) : nil
      end
    end
  end
end
