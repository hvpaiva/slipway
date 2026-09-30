# frozen_string_literal: true

require 'yaml'
require_relative 'error'
require_relative 'cli/theme'
require_relative 'cli/style'
require_relative 'names'

module Slipway
  Config = Data.define(:color, :theme, :editor, :group, :network_timeout, :parallel, :protocols, :path, :exists,
                       :variables)

  class Config
    class Error < Slipway::Error; end

    # A git transport name, spelled as a URL scheme. The names reach GIT_ALLOW_PROTOCOL joined by
    # colons, so a name holding a colon would allow a transport nobody listed.
    PROTOCOL = /\A[a-z][a-z0-9+.-]*\z/
    INTEGER = ->(text) { Integer(text, 10, exception: false) }
    PARALLEL = 1..16
    # Capped at a day: Thread#join, which enforces the deadline, takes a timeout past about 1.8e10
    # seconds as already passed.
    NETWORK_TIMEOUT = 1..86_400
    # Colon-separated like GIT_ALLOW_PROTOCOL; an empty field is kept so the check refuses it.
    LIST = ->(text) { text.split(':', -1) }
    # Once GIT_ALLOW_PROTOCOL is set it is git's whole policy, and git's own refusal of ext no
    # longer applies, so these stay refused even when listed.
    UNSAFE_PROTOCOLS = {
      'ext' => 'runs a command named in the URL',
      'fd' => 'reads from file descriptors'
    }.freeze

    # +parse+ reads the string an environment variable holds; what it cannot read comes back as
    # nil and fails the check with the key's expectation, or with +variable_expectation+ when the
    # variable is written in another form than the file's value. +refusal+ says why a value of the
    # right form is still refused, or returns nil.
    Setting = Data.define(:key, :variable, :default, :description, :valid, :expectation, :parse,
                          :variable_expectation, :refusal) do
      def initialize(parse: :itself.to_proc, variable_expectation: nil, refusal: ->(_) {}, **) = super

      def attribute = key.gsub(/(?=[A-Z])/, '_').downcase.to_sym

      def check(value, prefix, subject: "\"#{key}\" ", expectation: self.expectation)
        problem = valid.call(value) ? refusal.call(value) : expectation
        return value if problem.nil?

        raise Error, "#{prefix}: #{subject}#{problem}"
      end

      def from_variable(text)
        check(parse.call(text), variable, subject: '', expectation: variable_expectation || expectation)
      end

      def documentation = [description, default && "Default: #{Array(default).join(', ')}."].compact.join(' ')
    end

    SETTINGS = [
      Setting.new(key: 'color', variable: 'SLIPWAY_COLOR', default: CLI::Style::DEFAULT_MODE,
                  description: 'When to color output: auto, always or never.',
                  valid: ->(value) { CLI::Style::MODES.include?(value) },
                  expectation: "must be one of #{CLI::Style::MODES.join(', ')}"),
      Setting.new(key: 'editor', variable: 'SLIPWAY_EDITOR', default: nil,
                  description: 'Command line of the editor that slipway edit opens.',
                  valid: ->(value) { value.is_a?(String) }, expectation: 'must be a string'),
      Setting.new(key: 'group', variable: 'SLIPWAY_GROUP', default: 'default',
                  description: 'Group used when -n is not given.',
                  valid: ->(value) { Names.valid?(value) },
                  expectation: "must be a valid group name: #{Names::RULE}"),
      Setting.new(key: 'networkTimeout', variable: 'SLIPWAY_NETWORK_TIMEOUT', default: 60,
                  description: "Seconds, from #{NETWORK_TIMEOUT.min} to #{NETWORK_TIMEOUT.max}, a git network " \
                               'command may run before it is killed with the processes it started.',
                  valid: ->(value) { value.is_a?(Integer) && NETWORK_TIMEOUT.cover?(value) },
                  expectation: "must be an integer from #{NETWORK_TIMEOUT.min} to #{NETWORK_TIMEOUT.max}",
                  parse: INTEGER),
      Setting.new(key: 'parallel', variable: 'SLIPWAY_PARALLEL', default: 4,
                  description: "How many git network commands run at once, from #{PARALLEL.min} to #{PARALLEL.max}.",
                  valid: ->(value) { value.is_a?(Integer) && PARALLEL.cover?(value) },
                  expectation: "must be an integer from #{PARALLEL.min} to #{PARALLEL.max}", parse: INTEGER),
      Setting.new(key: 'protocols', variable: 'SLIPWAY_PROTOCOLS', default: %w[ssh https].freeze,
                  description: 'Transports git may use in network commands, as a list; any other transport is ' \
                               'refused, and so are ext and fd. Add file for local mirrors.',
                  valid: lambda { |value|
                    value.is_a?(Array) && !value.empty? && value.all? { it.is_a?(String) && PROTOCOL.match?(it) }
                  },
                  expectation: 'must be a list of lowercase git transport names, such as ssh, https or file',
                  variable_expectation: 'must be lowercase git transport names separated by colons, such as ssh:https',
                  parse: LIST,
                  refusal: lambda { |names|
                    unsafe = names.find { UNSAFE_PROTOCOLS.key?(it) }
                    "must not include #{unsafe}, which #{UNSAFE_PROTOCOLS[unsafe]}" if unsafe
                  }),
      Setting.new(key: 'theme', variable: 'SLIPWAY_THEME', default: CLI::Theme::DEFAULT_NAME,
                  description: 'Color theme: dark or light.',
                  valid: ->(value) { CLI::Theme::NAMES.include?(value) },
                  expectation: "must be one of #{CLI::Theme::NAMES.join(', ')}")
    ].freeze

    KEYS = SETTINGS.map(&:key).freeze
    DOCUMENTATION = SETTINGS.to_h { [it.key, it.documentation] }.freeze

    class Document
      Contents = Data.define(:values, :exists)

      def self.read(path, explicit:)
        text = File.read(path)
      rescue Errno::ENOENT
        raise Error, "#{path}: no such file" if explicit

        Contents.new(values: {}, exists: false)
      rescue SystemCallError => e
        raise Error.from_system_call(e, path)
      else
        Contents.new(values: new(path, text).values, exists: true)
      end

      def initialize(path, text)
        @path = path
        @text = text
      end

      def values
        document = parse
        return {} if document.nil?
        raise Error, "#{@path}: expected a mapping of keys to values" unless document.is_a?(Hash)

        document.to_h { |key, value| [key.to_s, setting(key).check(value, @path)] }
      end

      private

      def parse
        Psych.safe_load(@text, filename: @path, symbolize_names: false)
      rescue Psych::SyntaxError => e
        raise Error, "#{@path}: #{e.message.delete_prefix("(#{@path}): ")}"
      rescue Psych::Exception => e
        raise Error, "#{@path}: #{e.message}"
      end

      def setting(key)
        SETTINGS.find { it.key == key } ||
          raise(Error, "#{@path}: unknown key \"#{key}\" (known keys: #{KEYS.join(', ')})")
      end
    end

    def self.load(paths, env:, flags: {})
      path = paths.config_file
      contents = Document.read(path, explicit: paths.config_explicit?)
      resolved = SETTINGS.to_h { |setting| [setting.attribute, resolve(setting, flags, env, contents.values)] }
      # Each key whose value its environment variable supplied, with that variable's name, so a
      # message can point at the variable rather than at a file it outranks.
      variables = SETTINGS.select { from_variable?(it, flags, env) }.to_h { [it.key, it.variable] }.freeze
      new(path:, exists: contents.exists, variables:, **resolved)
    end

    def self.resolve(setting, flags, env, file)
      flag = flags[setting.attribute]
      return flag unless flag.nil?
      return setting.from_variable(env[setting.variable]) if from_variable?(setting, flags, env)

      file.fetch(setting.key, setting.default)
    end

    def self.from_variable?(setting, flags, env) = flags[setting.attribute].nil? && !env[setting.variable].to_s.empty?
    private_class_method :resolve, :from_variable?

    def exists? = exists

    def to_h = SETTINGS.to_h { [it.key, public_send(it.attribute)] }
  end
end
