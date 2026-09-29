# frozen_string_literal: true

require 'test_helper'

class ManBuiltinTest < Minitest::Test
  include CliHelper
  include Sandbox

  PAGES = %w[slipway.1 slipway-get.1 slipway-config.1 slipway-config-view.1].freeze
  PAGER_VARIABLES = Slipway::CLI::Builtins::ManCommand::USER_PAGER_VARIABLES

  def setup
    @calls = []
    @exec = ->(env, *argv) { @calls << [env, argv] }
  end

  def test_man_is_registered_among_the_settings_commands
    fixture = FixtureRegistry.new
    man = fixture.command('man')

    assert_equal 'Settings Commands', man.section
    assert_equal %w[path install], man.options.map(&:long)
    assert_equal ['--path', '--install[=DIR]'], man.options.map(&:label)
    candidates, = Slipway::CLI::Completer.new(fixture.registry).complete(['man', ''])

    assert_equal %w[get create config], candidates.map(&:first).first(3)
  end

  def test_execs_man_on_the_page_of_the_command
    with_pages do |dir, env|
      status, out, err = run_cli('man', 'config', 'view', registry: registry(dir), env:)

      assert_equal 0, status
      assert_empty out
      assert_empty err
      assert_equal [[{}, ['man', File.join(dir, 'slipway-config-view.1')]]], @calls
    end
  end

  def test_execs_the_root_page_without_a_command
    with_pages do |dir, env|
      run_cli('man', registry: registry(dir), env:)

      assert_equal ['man', File.join(dir, 'slipway.1')], @calls.first.last
    end
  end

  def test_color_adds_groff_no_sgr_and_a_less_termcap_palette_from_the_theme
    with_pages do |dir, env|
      run_cli('--color=always', 'man', 'get', registry: registry(dir), env:)

      assert_equal({ 'GROFF_NO_SGR' => '1',
                     'LESS_TERMCAP_md' => "\e[1m", 'LESS_TERMCAP_me' => "\e[0m",
                     'LESS_TERMCAP_us' => "\e[4;36m", 'LESS_TERMCAP_ue' => "\e[0m",
                     'LESS_TERMCAP_so' => "\e[7;33m", 'LESS_TERMCAP_se' => "\e[0m" }, @calls.first.first)
    end
  end

  def test_light_theme_changes_the_palette
    with_pages do |dir, env|
      run_cli('--color=always', 'man', 'get', registry: registry(dir), env: env.merge('SLIPWAY_THEME' => 'light'))

      assert_equal "\e[4;34m", @calls.first.first['LESS_TERMCAP_us']
    end
  end

  def test_no_color_means_an_untouched_environment
    with_pages do |dir, env|
      run_cli('man', 'get', registry: registry(dir), env:)
      run_cli('--color=never', 'man', 'get', registry: registry(dir), env:, tty: true)

      assert_equal [{}, {}], @calls.map(&:first)
    end
  end

  def test_user_pager_settings_are_respected
    with_pages do |dir, env|
      PAGER_VARIABLES.each do |variable|
        run_cli('--color=always', 'man', 'get', registry: registry(dir), env: env.merge(variable => 'x'))
      end
      run_cli('--color=always', 'man', 'get', registry: registry(dir), env: env.merge('MANPAGER' => ''))

      assert_equal [{}] * PAGER_VARIABLES.size, @calls.map(&:first).first(PAGER_VARIABLES.size)
      assert_equal '1', @calls.last.first['GROFF_NO_SGR']
    end
  end

  def test_path_prints_the_bundled_directory
    with_pages do |dir, env|
      status, out, err = run_cli('man', '--path', registry: registry(dir), env:)

      assert_equal 0, status
      assert_equal "#{dir}\n", out
      assert_empty err
      assert_empty @calls
    end
  end

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

  def test_missing_man_binary_is_an_error_with_the_help_alternative
    with_pages do |dir, env|
      status, out, err = run_cli('man', 'config', 'view', registry: registry(dir), env: env.merge('PATH' => dir))

      assert_equal 1, status
      assert_empty out
      assert_equal "error: man(1) not found; run 'slipway help config view' instead\n", err
      assert_empty @calls
    end
  end

  def test_missing_page_is_an_error
    with_sandbox do |env|
      Dir.mktmpdir('slipway-empty-') do |dir|
        status, _, err = run_cli('man', 'get', registry: registry(dir), env:)

        assert_equal 1, status
        assert_equal "error: manual page slipway-get.1 not found in #{dir}\n", err
      end
    end
  end

  def test_unknown_command_is_a_usage_error_with_a_hint
    with_pages do |dir, env|
      status, _, err = run_cli('man', 'bogus', registry: registry(dir), env:)

      assert_equal 2, status
      assert_equal "error: unknown command \"bogus\" for \"slipway\"\nRun 'slipway --help' for usage.\n", err
    end
  end

  def test_production_defaults_point_at_the_bundled_directory_and_kernel_exec
    man = Slipway::CLI::Builtins.man(program: 'slipway', resolve: -> { FixtureRegistry.new.registry })

    assert_equal File.expand_path('../../../man/man1', __dir__), Slipway::CLI::Builtins::MAN_DIR
    assert_equal 'man', man.name
  end

  private

  # A registry with get, config and the man builtin wired to the fake exec and +dir+.
  def registry(dir)
    fixture = FixtureRegistry.new
    registry = nil
    man = Slipway::CLI::Builtins.man(program: 'slipway', resolve: -> { registry }, man_dir: dir, exec: @exec)
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
