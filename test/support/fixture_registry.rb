# frozen_string_literal: true

require 'stringio'

# Exercises every feature of the command layer: verbs with enums, a repeatable and a required
# option, a nested group, a raw command and a positional whose candidates go on after a dot.
class FixtureRegistry
  Call = Data.define(:name, :args, :opts, :context)

  PROGRAM = 'slipway'
  VERSION = '0.1.0'
  DESCRIPTION = 'Slipway keeps a registry of the development projects on your machine.'
  TYPES = %w[projects groups].freeze
  FORMATS = %w[table wide json yaml name].freeze
  PROJECT_NAMES = %w[alpha beta].freeze
  # Each path explain completes, with the paths one level under it.
  FIELD_PATHS = { '' => %w[projects groups], 'projects' => %w[projects.kind projects.spec],
                  'projects.spec' => %w[projects.spec.path] }.freeze

  attr_reader :calls, :registry
  # An exception instance or class; once set, every handler raises it.
  attr_accessor :failure

  def initialize
    @calls = []
    @registry = Slipway::CLI::Registry.new(program: PROGRAM, version: VERSION, description: DESCRIPTION,
                                           globals: Slipway::CLI::Globals::ALL,
                                           commands: [get, create, explain, config, raw])
  end

  def run(*argv, env: {}, tty: false, err_tty: false, color: nil, theme: nil)
    out = StringIO.new
    err = StringIO.new
    context = Slipway::CLI::Context.new(out:, err:, env:, tty:, err_tty:)
    status = Slipway::CLI::Runner.new(registry, context, color:, theme:).run(argv)
    [status, out.string, err.string]
  end

  def command(*words) = registry.resolve(words).first

  private

  def handler(name)
    lambda do |context, args, opts|
      @calls << Call.new(name:, args:, opts:, context:)
      raise failure if failure
    end
  end

  def get
    Slipway::CLI::Command.new(
      name: 'get', aliases: %w[ls], summary: 'Display one or many resources', section: 'Basic Commands',
      description: 'Display one or many resources.',
      examples: [
        Slipway::CLI::Example.new(comment: 'List every project in the current group', command: 'get projects'),
        Slipway::CLI::Example.new(comment: 'List projects as JSON', command: 'get projects -o json')
      ],
      positionals: [
        Slipway::CLI::Positional.new(name: 'TYPE', enum: TYPES),
        Slipway::CLI::Positional.new(name: 'NAME', required: false, variadic: true,
                                     completer: ->(_given, _current) { PROJECT_NAMES })
      ],
      options: list_options,
      handler: handler('get')
    )
  end

  def list_options
    [
      Slipway::CLI::Option.new(long: 'output', short: 'o', argument: 'FORMAT', enum: FORMATS, default: 'table',
                               description: 'Output format.'),
      Slipway::CLI::Option.new(long: 'no-headers',
                               description: "When using the default output format, don't print headers."),
      Slipway::CLI::Option.new(long: 'selector', short: 'l', argument: 'EXPR',
                               description: 'Selector (label query) to filter on.')
    ]
  end

  def create
    Slipway::CLI::Command.new(
      name: 'create', summary: 'Create a resource', section: 'Basic Commands',
      positionals: [Slipway::CLI::Positional.new(name: 'TYPE', enum: TYPES),
                    Slipway::CLI::Positional.new(name: 'NAME')],
      options: create_options,
      handler: handler('create')
    )
  end

  def create_options
    [
      Slipway::CLI::Option.new(long: 'path', argument: 'DIR', required: true,
                               completer: ->(_given, _current) { Slipway::CLI::Completer::FILES },
                               description: 'Directory of the repository.'),
      Slipway::CLI::Option.new(long: 'label', argument: 'KEY=VALUE', repeatable: true, description: 'Label to set.'),
      Slipway::CLI::Option.new(long: 'output', argument: 'FORMAT', enum: %w[table yaml json], default: 'table',
                               description: 'Output format.')
    ]
  end

  def explain
    Slipway::CLI::Command.new(
      name: 'explain', summary: 'Describe the fields of a resource type', section: 'Basic Commands',
      positionals: [Slipway::CLI::Positional.new(name: 'FIELD', completer: lambda { |_given, current|
        field_paths(current)
      })],
      handler: handler('explain')
    )
  end

  # A path with paths under it goes on after a dot, so the shell adds no space after it.
  def field_paths(current)
    paths = FIELD_PATHS.fetch(current.rpartition('.').first, []).select { it.start_with?(current) }
    paths.any? { FIELD_PATHS.key?(it) } ? Slipway::CLI::Completer::NoSpace.new(paths) : paths
  end

  def config
    Slipway::CLI::Command.new(
      name: 'config', summary: 'Modify the configuration', section: 'Settings Commands',
      subcommands: [
        Slipway::CLI::Command.new(name: 'view', summary: 'Print the effective configuration',
                                  handler: handler('config view')),
        Slipway::CLI::Command.new(name: 'path', summary: 'Print the configuration file path',
                                  handler: handler('config path'))
      ]
    )
  end

  def raw
    Slipway::CLI::Command.new(
      name: 'raw', summary: 'Receive argv untouched', hidden: true, raw: true,
      positionals: [Slipway::CLI::Positional.new(name: 'WORDS', required: false, variadic: true)],
      handler: handler('raw')
    )
  end
end
