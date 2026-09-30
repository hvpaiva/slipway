# frozen_string_literal: true

require 'fileutils'

module Slipway
  module CLI
    module Builtins
      MAN_DIR = File.expand_path('../../../man/man1', __dir__)

      def self.all(program:, version:, resolve:, **man)
        [help(program:, resolve:), version(program:, version:), completion(program:), man(program:, resolve:, **man),
         complete(resolve:)]
      end

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
          handler: HelpCommand.new(resolve)
        )
      end

      def self.version(program:, version:)
        Command.new(
          name: 'version', summary: "Print the version of #{program}", section: 'Other Commands',
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

      # Keep these paths in step with the install lines in the CompletionScripts headers.
      def self.completion_examples(program)
        [
          Example.new(comment: 'Install bash completions where bash-completion loads them',
                      command: 'completion bash > "${XDG_DATA_HOME:-$HOME/.local/share}/bash-completion/completions/' \
                               "#{program}\""),
          Example.new(comment: 'Install zsh completions in a directory on your fpath',
                      command: "completion zsh > ~/.zfunc/_#{program}"),
          Example.new(comment: 'Install fish completions',
                      command: "completion fish > ~/.config/fish/completions/#{program}.fish")
        ]
      end

      # +paths+ is called with the environment and answers man_install_dir and man_db_dir for
      # a bare --install. +exec+ and +paths+ are injectable so tests can observe the calls.
      def self.man(program:, resolve:, man_dir: MAN_DIR, exec: Kernel.method(:exec), paths: nil)
        Command.new(
          name: 'man', section: 'Settings Commands', summary: 'Show the manual page of a command',
          description: "Show the manual page of #{program} or of one of its commands with man(1).\n" \
                       'The pages ship with the gem; --install copies them where man-db looks for user pages.',
          examples: man_examples,
          positionals: [Positional.new(name: 'COMMAND', required: false, variadic: true,
                                       completer: ->(given) { subcommand_names(resolve.call, given) })],
          options: man_options,
          handler: ManCommand.new(resolve, man_dir:, exec:, paths:)
        )
      end

      def self.man_examples
        [
          Example.new(comment: 'Read the page of a command', command: 'man get'),
          Example.new(comment: 'Install every page for man(1)', command: 'man --install'),
          Example.new(comment: 'Print the bundled page directory', command: 'man --path')
        ]
      end

      def self.man_options
        [
          Option.new(long: 'path', description: 'Print the directory of the bundled pages and exit.'),
          Option.new(long: 'install', argument: 'DIR', optional: true, implicit: true,
                     description: 'Copy every page into DIR, a man1 directory, or into ' \
                                  '${XDG_DATA_HOME:-~/.local/share}/man/man1.')
        ]
      end

      def self.complete(resolve:)
        Command.new(
          name: '__complete', summary: 'Print completion candidates for the given words', hidden: true, raw: true,
          positionals: [Positional.new(name: 'WORDS', required: false, variadic: true)],
          handler: ->(context, words, opts) { Completer.new(resolve.call).call(context, words, opts) }
        )
      end

      def self.subcommand_names(registry, given)
        registry.resolve(given).first.visible_subcommands.map(&:name)
      end

      # +resolve+ returns the registry when called, since the builtin is built before the
      # registry that holds it exists.
      class HelpCommand
        def initialize(resolve)
          @resolve = resolve
        end

        def call(context, words, _opts)
          registry = @resolve.call
          renderer = HelpRenderer.new(registry, context.style)
          command, path = registry.resolve(words)
          context.print(words.empty? ? renderer.root : renderer.command(command, path))
        end
      end

      class ManCommand
        # Any of these means the user configured the pager's look, so it is left alone.
        USER_PAGER_VARIABLES = %w[LESS_TERMCAP_md MANPAGER MANROFFOPT GROFF_NO_SGR].freeze
        RESET = "\e[0m"
        NO_DEFAULT_DIR = 'no default install directory is configured; pass --install=DIR'
        # man(1) looks for section 1 pages in the man1 directory of each MANPATH entry, so the
        # MANPATH line printed for any other directory would find nothing.
        SECTION_DIR = 'man1'
        NOT_A_SECTION_DIR = "invalid argument %s for --install: must be a #{SECTION_DIR} directory, " \
                            "such as ~/.local/share/man/#{SECTION_DIR}".freeze
        # An empty DIR would expand to the working directory.
        INSTALL_EMPTY = 'flag --install must not be empty'

        def initialize(resolve, man_dir:, exec:, paths:)
          @resolve = resolve
          @man_dir = man_dir
          @exec = exec
          @paths = paths
        end

        def call(context, args, opts)
          return context.puts(@man_dir) if opts[:path]
          return install(context, opts[:install]) if opts[:install]

          show(context, args)
        end

        private

        def registry = @resolve.call

        def show(context, words)
          _, path = registry.resolve(words)
          file = File.join(@man_dir, "#{[registry.program, *path].join('-')}.1")
          raise Slipway::Error, "manual page #{File.basename(file)} not found in #{@man_dir}" unless File.file?(file)
          raise Slipway::Error, missing_man_message(path) unless man?(context.env)

          @exec.call(pager_env(context), 'man', file)
        end

        def missing_man_message(path)
          "man(1) not found; run '#{[registry.program, 'help', *path].join(' ')}' instead"
        end

        def man?(env)
          env.fetch('PATH', '').split(File::PATH_SEPARATOR).any? { File.executable?(File.join(it, 'man')) }
        end

        # LESS_TERMCAP colors only take effect when groff stops emitting SGR itself, hence
        # GROFF_NO_SGR.
        def pager_env(context)
          return {} unless context.color? && USER_PAGER_VARIABLES.none? { set?(context.env[it]) }

          theme = context.style.theme
          { 'GROFF_NO_SGR' => '1',
            'LESS_TERMCAP_md' => sgr(theme.sgr(:help_header)), 'LESS_TERMCAP_me' => RESET,
            'LESS_TERMCAP_us' => sgr("4;#{theme.sgr(:help_flag)}"), 'LESS_TERMCAP_ue' => RESET,
            'LESS_TERMCAP_so' => sgr("7;#{theme.sgr(:status_warning)}"), 'LESS_TERMCAP_se' => RESET }
        end

        def sgr(parameters) = "\e[#{parameters}m"

        def set?(value) = !value.to_s.empty?

        def install(context, target)
          paths = @paths&.call(context.env)
          dir = target == true ? default_install_dir(paths) : named_install_dir(target)
          pages = Dir[File.join(@man_dir, '*.1')]
          raise Slipway::Error, "no manual pages found in #{@man_dir}" if pages.empty?

          FileUtils.mkdir_p(dir)
          pages.each do |page|
            FileUtils.cp(page, dir)
            context.puts("installed #{File.join(dir, File.basename(page))}")
          end
          context.puts(install_note(paths, dir))
        end

        def default_install_dir(paths)
          raise Slipway::Error, NO_DEFAULT_DIR if paths.nil?

          paths.man_install_dir
        end

        def named_install_dir(target)
          raise UsageError, INSTALL_EMPTY if target.strip.empty?

          dir = File.expand_path(target)
          raise UsageError, format(NOT_A_SECTION_DIR, target.inspect) unless File.basename(dir) == SECTION_DIR

          dir
        end

        # man-db adds ~/.local/share/man on its own only when ~/.local/bin is on PATH.
        def install_note(paths, dir)
          if paths && dir == paths.man_db_dir
            'man-db searches ~/.local/share/man when ~/.local/bin is on PATH; otherwise add it to MANPATH.'
          else
            %(export MANPATH="#{File.dirname(dir)}:$MANPATH")
          end
        end
      end
    end
  end
end
