# frozen_string_literal: true

require_relative 'paths'
require_relative 'config'
require_relative 'store'
require_relative 'git'
require_relative 'inspector'

module Slipway
  Runtime = Data.define(:config, :paths, :store, :git, :inspector, :clock, :env)

  # Everything a command needs for one run, built once per invocation from the context and
  # the parsed options. Tests build one with fakes and a temporary store instead.
  class Runtime
    CONFIG_FLAG = '--config'
    CONFIG_INLINE = "#{CONFIG_FLAG}=".freeze

    # The production factory: real git, the store under the data home, and the clock in UTC.
    def self.build(context, opts)
      paths = Paths.new(context.env, config: opts[:config])
      config = Config.load(paths, env: context.env, flags: opts.slice(:color, :group))
      clock = -> { Time.now.utc }
      git = Git::Repository.new
      new(config:, paths:, store: Store.new(root: paths.data_home, clock:), git:,
          inspector: Inspector.new(git:, clock:, home: paths.home), clock:, env: context.env)
    end

    # The [color, theme] pair the config file contributes, read before the command line is
    # parsed so a `--color` typed later still outranks it. A broken file yields no defaults;
    # the command that runs next raises the same error with its exit status.
    def self.color_defaults(context, argv)
      paths = Paths.new(context.env, config: config_flag(argv))
      config = Config.load(paths, env: context.env)
      [config.color, config.theme]
    rescue Config::Error
      [nil, nil]
    end

    # The value of `--config PATH` or `--config=PATH` before any `--`, or nil.
    def self.config_flag(argv)
      words = argv.take_while { it != '--' }
      words.each_with_index do |word, index|
        return words[index + 1] if word == CONFIG_FLAG
        return word.delete_prefix(CONFIG_INLINE) if word.start_with?(CONFIG_INLINE)
      end
      nil
    end
    private_class_method :config_flag

    # The group a command works in: the -n flag when typed, else the configured one.
    def group_for(opts) = opts[:group] || config.group
  end
end
