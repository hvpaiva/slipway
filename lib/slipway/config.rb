# frozen_string_literal: true

require 'yaml'
require_relative 'error'
require_relative 'cli/theme'
require_relative 'cli/style'
require_relative 'names'

module Slipway
  Config = Data.define(:color, :theme, :editor, :group, :path, :exists)

  # The settings in effect for one run: flag, then SLIPWAY_* variable, then the config
  # file, then the built-in default. +path+ is the file consulted, +exists+ whether it was there.
  class Config
    # Raised for a config file or variable that cannot be used; exits with status 1.
    class Error < Slipway::Error; end

    # One key of the config file: how it is checked and where else its value may come from.
    Setting = Data.define(:key, :variable, :default, :description, :valid, :expectation) do
      # Returns +value+ or raises Error naming +prefix+ (a path or a variable) and, for a
      # file, the quoted key.
      def check(value, prefix, quoted:)
        return value if valid.call(value)

        subject = quoted ? "\"#{key}\" " : ''
        raise Error, "#{prefix}: #{subject}#{expectation}"
      end

      # The CONFIGURATION entry of the man page for this key.
      def documentation = [description, default && "Default: #{default}."].compact.join(' ')
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
      Setting.new(key: 'theme', variable: 'SLIPWAY_THEME', default: CLI::Theme::DEFAULT_NAME,
                  description: 'Color theme: dark or light.',
                  valid: ->(value) { CLI::Theme::NAMES.include?(value) },
                  expectation: "must be one of #{CLI::Theme::NAMES.join(', ')}")
    ].freeze

    KEYS = SETTINGS.map(&:key).freeze
    # The text of the man page's CONFIGURATION section, one entry per key.
    DOCUMENTATION = SETTINGS.to_h { [it.key, it.documentation] }.freeze

    # Reads and validates the config file itself; +values+ holds only the keys it set.
    class Document
      Contents = Data.define(:values, :exists)

      # A missing default file is an empty document; a missing explicit file is an error.
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

        document.to_h { |key, value| [key.to_s, setting(key).check(value, @path, quoted: true)] }
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

    # Resolves every setting for +paths+' config file. +flags+ may carry :color and :group.
    def self.load(paths, env:, flags: {})
      path = paths.config_file
      contents = Document.read(path, explicit: paths.config_explicit?)
      resolved = SETTINGS.to_h { |setting| [setting.key.to_sym, resolve(setting, flags, env, contents.values)] }
      new(path:, exists: contents.exists, **resolved)
    end

    def self.resolve(setting, flags, env, file)
      flag = flags[setting.key.to_sym]
      return flag unless flag.nil?

      variable = env[setting.variable]
      return setting.check(variable, setting.variable, quoted: false) unless variable.nil? || variable.empty?

      file.fetch(setting.key, setting.default)
    end
    private_class_method :resolve

    # True when the configuration file was present, whatever it held.
    def exists? = exists

    # String keys in the documented order, as `config view` prints them.
    def to_h = KEYS.to_h { [it, public_send(it)] }
  end
end
