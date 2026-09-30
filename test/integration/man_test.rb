# frozen_string_literal: true

require 'test_helper'

class ManIntegrationTest < Minitest::Test
  include IntegrationHelper

  MAN_DIR = File.join(ROOT, 'man', 'man1')
  PAGES = Dir.children(MAN_DIR).sort.freeze

  def test_path_prints_the_bundled_page_directory
    with_home do |env|
      assert_equal [0, "#{MAN_DIR}\n", ''], slipway('man', '--path', env:)
      assert_equal 24, PAGES.size
    end
  end

  def test_install_copies_every_page_under_xdg_data_home
    with_home do |env|
      target = File.join(env['XDG_DATA_HOME'], 'man', 'man1')
      status, out, err = slipway('man', '--install', env:)

      assert_equal [0, ''], [status, err]
      assert_equal PAGES, Dir.children(target).sort
      assert_equal [*PAGES.map { "installed #{File.join(target, it)}" },
                    'man-db searches ~/.local/share/man when ~/.local/bin is on PATH; otherwise add it to MANPATH.'],
                   out.lines(chomp: true)
      assert_equal File.read(File.join(MAN_DIR, 'slipway.1')), File.read(File.join(target, 'slipway.1'))
    end
  end

  def test_install_into_a_named_directory_prints_a_manpath_line
    with_home do |env|
      target = File.join(env['HOME'], 'opt', 'share', 'man', 'man1')
      status, out, err = slipway('man', "--install=#{target}", env:)

      assert_equal [0, ''], [status, err]
      assert_equal PAGES, Dir.children(target).sort
      assert_equal %(export MANPATH="#{File.join(env['HOME'], 'opt', 'share', 'man')}:$MANPATH"), out.lines.last.chomp
    end
  end

  def test_install_refuses_a_directory_that_is_not_man1
    with_home do |env|
      target = File.join(env['HOME'], 'sw', 'mandir')

      assert_equal [2, '', "error: invalid argument #{target.inspect} for --install: must be a man1 directory, " \
                           "such as ~/.local/share/man/man1\nSee 'slipway man --help' for usage.\n"],
                   slipway('man', "--install=#{target}", env:)
      refute_path_exists File.join(env['HOME'], 'sw')
    end
  end

  def test_install_refuses_a_directory_given_after_a_space
    with_home do |env|
      target = File.join(env['HOME'], 'opt', 'share', 'man', 'man1')

      assert_equal [2, '', "error: unexpected argument #{target.inspect}; pass the directory as --install=DIR\n" \
                           "See 'slipway man --help' for usage.\n"],
                   slipway('man', '--install', target, env:)
      refute_path_exists File.join(env['HOME'], 'opt')
      refute_path_exists File.join(env['XDG_DATA_HOME'], 'man')
    end
  end

  def test_install_refuses_an_empty_directory_even_from_inside_man1
    with_home do |env|
      section = FileUtils.mkdir_p(File.join(env['HOME'], 'share', 'man', 'man1')).first

      assert_equal [2, '', "error: flag --install must not be empty\nSee 'slipway man --help' for usage.\n"],
                   slipway('man', '--install=', env:, chdir: section)
      assert_empty Dir.children(section)
    end
  end

  def test_without_man_on_path_the_help_command_is_offered_instead
    with_home do |env|
      status, out, err = slipway('man', 'config', 'view', env: env.merge('PATH' => '/nonexistent'))

      assert_equal [1, '', "error: man(1) not found; run 'slipway help config view' instead\n"], [status, out, err]
      assert_equal [2, '', "error: unknown command \"bogus\" for \"slipway\"\nRun 'slipway --help' for usage.\n"],
                   slipway('man', 'bogus', env:)
    end
  end
end
