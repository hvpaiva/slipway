# frozen_string_literal: true

require_relative 'base'
require_relative '../yaml'

module Slipway
  module Commands
    # Named apart from Slipway::Config, the settings it displays.
    module ConfigCommand
      DESCRIPTION = 'Inspect the configuration that slipway resolved from flags, environment variables and ' \
                    'the configuration file.'
      NOT_FOUND = ' (not found)'

      def self.command(factory)
        CLI::Command.new(
          name: 'config', summary: 'Inspect the configuration in effect', section: 'Settings Commands',
          description: DESCRIPTION, subcommands: [View.command(factory), Path.command(factory)]
        )
      end

      class View < Base
        DESCRIPTION = "Display the configuration in effect.\n\n" \
                      'Prints every setting as YAML after applying the precedence flag, then SLIPWAY_* ' \
                      'environment variable, then configuration file, then built-in default. The first line ' \
                      'names the configuration file that was consulted, and says (not found) when the default ' \
                      'file does not exist. A file named by --config or SLIPWAY_CONFIG must exist.'

        def self.command(factory)
          CLI::Command.new(
            name: 'view', summary: 'Display the configuration in effect', description: DESCRIPTION,
            examples: [
              CLI::Example.new(comment: 'Show the settings in effect', command: 'config view'),
              CLI::Example.new(comment: 'Show the settings another file would give',
                               command: 'config view --config ~/work/slipway.yaml')
            ],
            handler: new(factory)
          )
        end

        def run(runtime, context, _args, _opts)
          config = runtime.config
          comment = "# #{config.path}"
          comment += NOT_FOUND unless config.exists?
          context.puts(context.paint(:muted, comment))
          context.print(Yaml.dump(config.to_h))
        end
      end

      class Path < Base
        DESCRIPTION = "Display the path of the configuration file.\n\n" \
                      'Prints the file that slipway reads: --config, then SLIPWAY_CONFIG, then ' \
                      '$XDG_CONFIG_HOME/slipway/config.yaml. When the default file does not exist, its path is ' \
                      'still printed and a note on stderr says so; a file named by --config or SLIPWAY_CONFIG ' \
                      'must exist.'
        MISSING = 'The file does not exist; slipway uses its defaults.'

        def self.command(factory)
          CLI::Command.new(
            name: 'path', summary: 'Display the path of the configuration file', description: DESCRIPTION,
            examples: [CLI::Example.new(comment: 'Print the path of the configuration file', command: 'config path')],
            handler: new(factory)
          )
        end

        # stdout stays the bare path so "$(slipway config path)" can open the file before it exists.
        def run(runtime, context, _args, _opts)
          config = runtime.config
          context.puts(config.path)
          context.warn(context.paint_err(:muted, MISSING)) unless config.exists?
        end
      end
    end
  end
end
