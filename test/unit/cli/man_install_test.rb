# frozen_string_literal: true

require 'test_helper'

class ManInstallTest < Minitest::Test
  include ManHelper

  def test_install_into_a_given_directory_prints_each_file_and_a_manpath_line
    with_pages do |dir, env|
      target = File.join(env['HOME'], 'opt', 'man', 'man1')
      status, out, err = run_cli('man', "--install=#{target}", registry: registry(dir), env:)

      assert_equal 0, status
      assert_empty err
      assert_equal PAGES.sort, Dir.children(target).sort
      assert_equal [*PAGES.sort.map { "installed #{File.join(target, it)}" },
                    %(export MANPATH="#{File.join(env['HOME'], 'opt', 'man')}:$MANPATH")], out.lines(chomp: true)
    end
  end

  def test_install_defaults_to_the_xdg_data_home_and_explains_man_db_discovery
    with_pages do |dir, env|
      status, out, = run_cli('man', '--install', registry: registry(dir), env:)

      assert_equal 0, status
      assert_equal PAGES.sort, Dir.children(File.join(env['XDG_DATA_HOME'], 'man', 'man1')).sort
      assert_equal 'man-db searches ~/.local/share/man when ~/.local/bin is on PATH; otherwise add it to MANPATH.',
                   out.lines.last.chomp
    end
  end

  def test_install_under_a_custom_xdg_data_home_prints_the_manpath_line_instead
    with_pages do |dir, env|
      data = File.join(env['HOME'], 'data')
      _, out, = run_cli('man', '--install', registry: registry(dir), env: env.merge('XDG_DATA_HOME' => data))

      assert_equal %(export MANPATH="#{File.join(data, 'man')}:$MANPATH"), out.lines.last.chomp
      assert_path_exists File.join(data, 'man', 'man1', 'slipway.1')
    end
  end

  def test_relative_xdg_data_home_is_ignored
    with_pages do |dir, env|
      run_cli('man', '--install', registry: registry(dir), env: env.merge('XDG_DATA_HOME' => 'relative/dir'))

      assert_path_exists File.join(env['HOME'], '.local', 'share', 'man', 'man1', 'slipway.1')
    end
  end

  def test_install_with_no_pages_is_an_error
    with_sandbox do |env|
      Dir.mktmpdir('slipway-empty-') do |dir|
        status, out, err = run_cli('man', '--install', registry: registry(dir), env:)

        assert_equal 1, status
        assert_empty out
        assert_equal "error: no manual pages found in #{dir}\n", err
      end
    end
  end

  def test_install_without_a_paths_factory_needs_an_explicit_directory
    with_pages do |dir, env|
      man = Slipway::CLI::Builtins.man(program: 'slipway', resolve: -> {}, man_dir: dir, exec: recorded_exec)
      registry = Slipway::CLI::Registry.new(program: 'slipway', version: '0.1.0', description: 'Slipway.',
                                            globals: Slipway::CLI::Globals::ALL, builtins: false, commands: [man])
      status, _, err = run_cli('man', '--install', registry:, env:)

      assert_equal 1, status
      assert_equal "error: no default install directory is configured; pass --install=DIR\n", err
    end
  end
end
