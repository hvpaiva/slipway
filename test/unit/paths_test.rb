# frozen_string_literal: true

require 'test_helper'
require 'slipway/paths'

class PathsTest < Minitest::Test
  HOME = '/home/pat'

  def test_config_file_defaults_to_dot_config_under_home
    assert_equal '/home/pat/.config/slipway/config.yaml', paths.config_file
    refute_predicate paths, :config_explicit?
  end

  def test_config_file_follows_an_absolute_xdg_config_home
    assert_equal '/etc/xdg/slipway/config.yaml', paths('XDG_CONFIG_HOME' => '/etc/xdg').config_file
  end

  def test_relative_and_empty_xdg_values_are_ignored
    assert_equal '/home/pat/.config/slipway/config.yaml', paths('XDG_CONFIG_HOME' => 'cfg').config_file
    assert_equal '/home/pat/.config/slipway/config.yaml', paths('XDG_CONFIG_HOME' => '').config_file
    assert_equal '/home/pat/.local/share/slipway', paths('XDG_DATA_HOME' => './data').data_home
    assert_equal '/home/pat/.local/share/man/man1', paths('XDG_DATA_HOME' => '~/share').man_install_dir
  end

  def test_slipway_config_outranks_xdg_and_marks_the_file_explicit
    subject = paths('SLIPWAY_CONFIG' => '/srv/slipway.yaml', 'XDG_CONFIG_HOME' => '/etc/xdg')

    assert_equal '/srv/slipway.yaml', subject.config_file
    assert_predicate subject, :config_explicit?
  end

  def test_the_config_flag_outranks_slipway_config
    subject = paths('SLIPWAY_CONFIG' => '/srv/slipway.yaml', config: 'local.yaml')

    assert_equal 'local.yaml', subject.config_file
    assert_predicate subject, :config_explicit?
  end

  def test_empty_flag_and_variable_count_as_unset
    subject = paths('SLIPWAY_CONFIG' => '', config: '')

    assert_equal '/home/pat/.config/slipway/config.yaml', subject.config_file
    refute_predicate subject, :config_explicit?
  end

  def test_tilde_in_slipway_variables_expands_to_the_given_home
    assert_equal '/home/pat/cfg/s.yaml', paths('SLIPWAY_CONFIG' => '~/cfg/s.yaml').config_file
    assert_equal '/home/pat/registry', paths('SLIPWAY_DATA_HOME' => '~/registry').data_home
    assert_equal '/home/pat', paths('SLIPWAY_DATA_HOME' => '~').data_home
    assert_equal '~pat/registry', paths('SLIPWAY_DATA_HOME' => '~pat/registry').data_home
  end

  def test_data_home_precedence
    assert_equal '/home/pat/.local/share/slipway', paths.data_home
    assert_equal '/mnt/data/slipway', paths('XDG_DATA_HOME' => '/mnt/data').data_home
    assert_equal '/srv/reg', paths('SLIPWAY_DATA_HOME' => '/srv/reg', 'XDG_DATA_HOME' => '/mnt/data').data_home
    assert_equal '/mnt/data/slipway', paths('SLIPWAY_DATA_HOME' => '', 'XDG_DATA_HOME' => '/mnt/data').data_home
  end

  def test_man_install_dir_follows_xdg_data_home_only
    assert_equal '/home/pat/.local/share/man/man1', paths.man_install_dir
    assert_equal '/mnt/data/man/man1', paths('XDG_DATA_HOME' => '/mnt/data').man_install_dir
    assert_equal '/mnt/data/man/man1',
                 paths('XDG_DATA_HOME' => '/mnt/data', 'SLIPWAY_DATA_HOME' => '/x').man_install_dir
  end

  def test_home_falls_back_to_the_account_home_when_unset_or_empty
    assert_equal HOME, paths.home
    assert_equal Dir.home, Slipway::Paths.new({}).home
    assert_equal Dir.home, Slipway::Paths.new({ 'HOME' => '' }).home
    assert_equal File.join(Dir.home, '.config', 'slipway', 'config.yaml'), Slipway::Paths.new({}).config_file
  end

  def test_variable_names_are_published_as_constants
    assert_equal 'SLIPWAY_CONFIG', Slipway::Paths::CONFIG_VARIABLE
    assert_equal 'SLIPWAY_DATA_HOME', Slipway::Paths::DATA_HOME_VARIABLE
    assert_equal 'XDG_CONFIG_HOME', Slipway::Paths::XDG_CONFIG_HOME
    assert_equal 'XDG_DATA_HOME', Slipway::Paths::XDG_DATA_HOME
  end

  private

  def paths(config: nil, **env)
    Slipway::Paths.new({ 'HOME' => HOME }.merge(env), config:)
  end
end
