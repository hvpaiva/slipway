# frozen_string_literal: true

module Slipway
  module CLI
    # Commands every registry gets for free: help, version, completion and the hidden
    # completion endpoint. They are ordinary registry entries.
    module Builtins
      def self.all(program:, version:, resolve:)
        [help(program:, resolve:), version(program:, version:), completion(program:), complete(resolve:)]
      end

      # The one-line version report shared by `version` and `--version`.
      def self.version_line(program, version)
        "#{program} #{version} (ruby #{RUBY_VERSION}) [#{Gem::Platform.local}]"
      end

      def self.help(program:, resolve:)
        Command.new(
          name: 'help', summary: 'Help about any command', section: 'Other Commands',
          description: "Help provides help for any command in the application.\n" \
                       "Type #{program} help [path to command] for full details.",
          examples: [Example.new(comment: 'Show the help of a nested command', command: 'help config view')],
          positionals: [Positional.new(name: 'COMMAND', required: false, variadic: true,
                                       completer: ->(given) { subcommand_names(resolve.call, given) })],
          handler: ->(context, args, _opts) { HelpCommand.new(resolve.call).call(context, args) }
        )
      end

      def self.version(program:, version:)
        Command.new(
          name: 'version', summary: 'Print the client version', section: 'Other Commands',
          description: "Print the version of #{program}, the Ruby it runs on and the platform.",
          examples: [Example.new(comment: 'Print the version', command: 'version')],
          handler: ->(context, _args, _opts) { context.puts(version_line(program, version)) }
        )
      end

      def self.completion(program:)
        shells = CompletionScripts::SHELLS.join(', ')
        Command.new(
          name: 'completion', section: 'Settings Commands',
          summary: "Output shell completion code for the specified shell (#{shells})",
          description: "Output shell completion code for the specified shell (#{shells}).\n" \
                       'The shell code must be evaluated to provide interactive completion of commands, ' \
                       'resource types and names.',
          examples: completion_examples(program),
          positionals: [Positional.new(name: 'SHELL', enum: CompletionScripts::SHELLS)],
          handler: ->(context, args, _opts) { context.print(CompletionScripts.render(args.first, program)) }
        )
      end

      def self.completion_examples(program)
        [
          Example.new(comment: 'Load completions into the current bash session',
                      command: 'completion bash | source /dev/stdin'),
          Example.new(comment: 'Install fish completions',
                      command: "completion fish > ~/.config/fish/completions/#{program}.fish")
        ]
      end

      def self.complete(resolve:)
        Command.new(
          name: '__complete', summary: 'Print completion candidates for the given words', hidden: true, raw: true,
          positionals: [Positional.new(name: 'WORDS', required: false, variadic: true)],
          handler: ->(context, words, _opts) { Completer.new(resolve.call).call(context, words) }
        )
      end

      def self.subcommand_names(registry, given)
        registry.resolve(given).first.visible_subcommands.map(&:name)
      end

      # `slipway help [COMMAND...]` renders the same page as `slipway COMMAND... --help`.
      class HelpCommand
        def initialize(registry)
          @registry = registry
        end

        def call(context, words)
          renderer = HelpRenderer.new(@registry, context.style)
          command, path = @registry.resolve(words)
          context.print(words.empty? ? renderer.root : renderer.command(command, path))
        end
      end
    end
  end
end
