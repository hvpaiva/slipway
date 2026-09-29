# frozen_string_literal: true

require 'test_helper'

class SandboxTest < Minitest::Test
  include Sandbox

  def test_with_sandbox_yields_xdg_directories_inside_a_fresh_home
    with_sandbox do |env|
      refute_equal Dir.home, env['HOME']
      assert_equal File.join(env['HOME'], '.config'), env['XDG_CONFIG_HOME']
      assert_equal File.join(env['HOME'], '.local', 'share'), env['XDG_DATA_HOME']
      assert_path_exists env['XDG_CONFIG_HOME']
      assert_path_exists env['XDG_DATA_HOME']
      assert_equal 'dumb', env['TERM']
    end
  end

  def test_with_sandbox_removes_the_home_afterwards
    home = with_sandbox { |env| env['HOME'] }

    refute_path_exists home
  end
end
