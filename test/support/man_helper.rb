# frozen_string_literal: true

require 'tmpdir'
require_relative 'cli_helper'
require_relative 'fixture_registry'
require_relative 'sandbox'

# The man builtin reads pages from a scratch directory and records its man(1) calls, since a
# real exec would replace the test process.
module ManHelper
  include CliHelper
  include Sandbox

  PAGES = %w[slipway.1 slipway-get.1 slipway-config.1 slipway-config-view.1].freeze

  private

  def man_calls = @man_calls ||= []

  def recorded_exec = ->(env, *argv) { man_calls << [env, argv] }

  def registry(dir)
    fixture = FixtureRegistry.new
    registry = nil
    man = Slipway::CLI::Builtins.man(program: 'slipway', resolve: -> { registry }, man_dir: dir, exec: recorded_exec,
                                     paths: Slipway::Paths.method(:new))
    registry = Slipway::CLI::Registry.new(program: 'slipway', version: '0.1.0', description: 'Slipway.',
                                          globals: Slipway::CLI::Globals::ALL, builtins: false,
                                          commands: [fixture.command('get'), fixture.command('config'), man])
  end

  def with_pages
    with_sandbox do |env|
      Dir.mktmpdir('slipway-man-') do |dir|
        PAGES.each { File.write(File.join(dir, it), ".TH #{it.upcase} 1\n") }
        yield dir, env
      end
    end
  end
end
