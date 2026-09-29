# frozen_string_literal: true

require 'fileutils'
require 'open3'
require 'psych'
require 'rbconfig'
require_relative 'git_fixtures'
require_relative 'sandbox'

module IntegrationHelper
  include GitFixtures
  include Sandbox

  ROOT = File.expand_path('../..', __dir__)
  LIB = File.join(ROOT, 'lib')
  EXE = File.join(ROOT, 'exe', 'slipway')
  # -w: a warning on stderr fails the assertion.
  COMMAND = [RbConfig.ruby, '-w', '-I', LIB, EXE].freeze
  # kubectl's HumanDuration: 4s, 2m10s, 3h, 2d5h, 2y319d, 9y.
  DURATION = /\d+(s|m|m\d+s|h|h\d+m|d|d\d+h|y|y\d+d)/
  AGE = /\A#{DURATION}\z/
  # A fixed creationTimestamp, so json and yaml output is the same on every run.
  CREATED = '2026-09-01T09:00:00Z'

  def with_home
    with_sandbox do |env|
      yield env.merge('GIT_CONFIG_GLOBAL' => '/dev/null', 'GIT_CONFIG_NOSYSTEM' => '1', 'LC_ALL' => 'C')
    end
  end

  # Only the keys of +env+ reach the process, so no SLIPWAY_* or color variable of the
  # developer leaks in.
  def slipway(*, env:, stdin: nil, chdir: nil)
    options = { unsetenv_others: true, stdin_data: stdin }
    options[:chdir] = chdir if chdir
    out, err, status = Open3.capture3(env, *COMMAND, *, **options)
    [status.exitstatus, out, err]
  end

  def slipway!(*args, env:, stdin: nil)
    status, out, err = slipway(*args, env:, stdin:)

    assert_equal [0, ''], [status, err], "slipway #{args.join(' ')} was expected to succeed quietly"
    out
  end

  # A nil state builds nothing, so the project shows as Missing.
  def repo(env, name, state = 'clean')
    build_repo(File.join(env['HOME'], 'dev', name), state) if state
    "~/dev/#{name}"
  end

  def manifest(kind, name, group: nil, labels: nil, created: CREATED, **spec)
    metadata = { 'name' => name }
    metadata['group'] = group if group
    metadata['labels'] = labels if labels
    metadata['creationTimestamp'] = created if created
    Psych.safe_dump({ 'kind' => kind, 'metadata' => metadata, 'spec' => spec.transform_keys(&:to_s) })
  end

  def seed(env, *manifests) = slipway!('apply', '-f', '-', env:, stdin: manifests.join)

  # +body+ receives the file to edit as $1.
  def editor_script(env, name, body)
    dir = File.join(env['HOME'], 'bin')
    FileUtils.mkdir_p(dir)
    path = File.join(dir, name)
    File.write(path, "#!/bin/sh\n#{body}\n")
    File.chmod(0o755, path)
    path
  end

  def data_home(env) = File.join(env.fetch('XDG_DATA_HOME'), 'slipway')

  def config_file(env) = File.join(env.fetch('XDG_CONFIG_HOME'), 'slipway', 'config.yaml')

  def write_config(env, text)
    path = config_file(env)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, text)
    path
  end

  def table(text) = text.lines(chomp: true).map { it.split(/ {3,}/) }

  # An :age cell only has to read as a duration, since the registry is created moments before
  # it is listed.
  def assert_table(expected, text)
    actual = table(text).each_with_index.map do |row, line|
      row.each_with_index.map { |cell, column| expected.dig(line, column) == :age && cell.match?(AGE) ? :age : cell }
    end

    assert_equal expected, actual
  end

  def scrub_age(text) = text.gsub(/^(\s*Age: +)\S+$/, '\1<age>')
end
