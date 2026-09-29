# frozen_string_literal: true

require 'yaml'
require_relative 'error'
require_relative 'cli/theme'
require_relative 'cli/style'
require_relative 'names'

module Slipway
  Config = Data.define(:color, :theme, :editor, :group, :path, :exists)

  class Config
    class Error < Slipway::Error; end

    Setting = Data.define(:key, :variable, :default, :description, :valid, :expectation) do
      def check(value, prefix, quoted:)
        return value if valid.call(value)

        subject = quoted ? "\"#{key}\" " : ''
        raise Error, "#{prefix}: #{subject}#{expectation}"
      end

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

    def exists? = exists

    def to_h = KEYS.to_h { [it, public_send(it)] }
  end
end
