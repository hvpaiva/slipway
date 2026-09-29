# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'

module Sandbox
  def with_sandbox
    Dir.mktmpdir('slipway-') do |home|
      yield sandbox_env(home)
    end
  end

  # PATH stays so git can run; TERM=dumb keeps color off in auto mode.
  def sandbox_env(home)
    config = File.join(home, '.config')
    data = File.join(home, '.local', 'share')
    FileUtils.mkdir_p([config, data])
    { 'HOME' => home, 'XDG_CONFIG_HOME' => config, 'XDG_DATA_HOME' => data,
      'PATH' => ENV.fetch('PATH'), 'TERM' => 'dumb' }
  end
end
