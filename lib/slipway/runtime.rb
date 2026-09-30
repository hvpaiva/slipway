# frozen_string_literal: true

require_relative 'paths'
require_relative 'config'
require_relative 'store'
require_relative 'git'
require_relative 'inspector'

module Slipway
  # Tests build one with fakes and a temporary store instead of calling build.
  class Runtime
    CONFIG_FLAG = '--config'
    CONFIG_INLINE = "#{CONFIG_FLAG}=".freeze

    attr_reader :config, :paths, :store, :git, :inspector, :clock, :env

    def self.build(context, opts)
      paths = Paths.new(context.env, config: opts[:config])
      config = Config.load(paths, env: context.env, flags: opts.slice(:color, :group))
      clock = -> { Time.now.utc }
      # The variable outranks the file, so a transport added to the file would change nothing.
      protocols_source = config.variables.fetch('protocols') { %("protocols" in #{config.path}) }
      git = Git::Repository.new(network_timeout: config.network_timeout, protocols: config.protocols, protocols_source:)
      new(config:, paths:, store: Store.new(root: paths.data_home, clock:), git:,
          inspector: Inspector.new(git:, clock:, home: paths.home), clock:, env: context.env)
    end

    # Read before the command line is parsed, so a `--color` typed later still outranks it.
    # A broken file yields no defaults; the command that runs next raises the same error with
    # its exit status.
    def self.color_defaults(context, argv)
      paths = Paths.new(context.env, config: config_flag(argv))
      config = Config.load(paths, env: context.env)
      [config.color, config.theme]
    rescue Config::Error
      [nil, nil]
    end

    def self.config_flag(argv)
      words = argv.take_while { it != '--' }
      words.each_with_index do |word, index|
        return words[index + 1] if word == CONFIG_FLAG
        return word.delete_prefix(CONFIG_INLINE) if word.start_with?(CONFIG_INLINE)
      end
      nil
    end
    private_class_method :config_flag

    def initialize(config:, paths:, store:, git:, inspector:, clock:, env:)
      @config = config
      @paths = paths
      @store = store
      @git = git
      @inspector = inspector
      @clock = clock
      @env = env
    end

    def group_for(opts) = opts[:group] || config.group

    # Leaves the environment out so a debugging print never dumps every variable of the process.
    def inspect = "#<#{self.class.name} data_home=#{store.root.inspect} config=#{config.to_h.inspect}>"
  end
end
