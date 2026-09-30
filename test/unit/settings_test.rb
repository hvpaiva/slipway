# frozen_string_literal: true

require 'test_helper'
require 'slipway/paths'
require 'slipway/settings'

class SettingsTest < Minitest::Test
  include SettingsHelper

  def test_defaults_when_the_default_file_is_missing
    with_sandbox do |env|
      settings = load(env)

      assert_equal %w[auto dark default], [settings.color, settings.theme, settings.group]
      assert_equal [60, %w[ssh https]], [settings.network_timeout, settings.protocols]
      assert_nil settings.editor
      assert_equal File.join(env['XDG_CONFIG_HOME'], 'slipway', 'config.yaml'), settings.path
      refute_predicate settings, :exists?
    end
  end

  def test_file_values_override_the_defaults
    with_sandbox do |env|
      write(env, "color: never\ntheme: light\neditor: code --wait\ngroup: work\n")
      settings = load(env)

      assert_equal %w[never light], [settings.color, settings.theme]
      assert_equal 'code --wait', settings.editor
      assert_equal 'work', settings.group
      assert_predicate settings, :exists?
    end
  end

  def test_empty_and_comment_only_files_count_as_present_defaults
    with_sandbox do |env|
      write(env, '')

      assert_predicate load(env), :exists?
      assert_equal 'auto', load(env).color

      write(env, "# nothing here yet\n")

      assert_equal 'default', load(env).group
    end
  end

  def test_environment_outranks_the_file
    with_sandbox do |env|
      write(env, "color: never\ntheme: light\neditor: nano\ngroup: work\n")
      env = env.merge('SLIPWAY_COLOR' => 'always', 'SLIPWAY_THEME' => 'dark',
                      'SLIPWAY_EDITOR' => 'vim', 'SLIPWAY_GROUP' => 'home')
      settings = load(env)

      assert_equal %w[always dark vim home], [settings.color, settings.theme, settings.editor, settings.group]
    end
  end

  def test_empty_environment_values_count_as_unset
    with_sandbox do |env|
      write(env, "color: never\ngroup: work\n")
      settings = load(env.merge('SLIPWAY_COLOR' => '', 'SLIPWAY_GROUP' => '', 'SLIPWAY_THEME' => ''))

      assert_equal %w[never dark work], [settings.color, settings.theme, settings.group]
    end
  end

  def test_flags_outrank_the_environment
    with_sandbox do |env|
      write(env, "color: never\ngroup: work\n")
      settings = load(env.merge('SLIPWAY_COLOR' => 'auto', 'SLIPWAY_GROUP' => 'home'),
                      flags: { color: 'always', group: 'lab', help: false })

      assert_equal 'always', settings.color
      assert_equal 'lab', settings.group
    end
  end

  def test_explicit_paths_are_read_and_reported
    with_sandbox do |env|
      file = File.join(env['HOME'], 'custom.yaml')
      File.write(file, "theme: light\n")

      by_flag = load(env, config: file)
      by_variable = load(env.merge('SLIPWAY_CONFIG' => file))

      assert_equal [file, 'light', true], [by_flag.path, by_flag.theme, by_flag.exists?]
      assert_equal [file, 'light', true], [by_variable.path, by_variable.theme, by_variable.exists?]
    end
  end

  def test_missing_explicit_file_is_an_error
    with_sandbox do |env|
      file = File.join(env['HOME'], 'missing.yaml')

      assert_settings_error "#{file}: no such file", env, config: file
      assert_settings_error "#{file}: no such file", env.merge('SLIPWAY_CONFIG' => file)
    end
  end

  def test_unreadable_file_reports_the_system_error
    with_sandbox do |env|
      dir = File.join(env['HOME'], 'dir.yaml')
      Dir.mkdir(dir)

      assert_settings_error "#{dir}: Is a directory", env, config: dir
    end
  end

  def test_non_mapping_document_is_an_error
    with_sandbox do |env|
      assert_file_error 'expected a mapping of keys to values', env, "- color\n- theme\n"
      assert_file_error 'expected a mapping of keys to values', env, "just a string\n"
    end
  end

  def test_unknown_key_lists_the_known_keys
    with_sandbox do |env|
      known = '(known keys: color, editor, group, networkTimeout, parallel, protocols, theme)'

      assert_file_error "unknown key \"colour\" #{known}", env, "colour: never\n"
      assert_file_error "unknown key \"1\" #{known}", env, "1: never\n"
    end
  end

  def test_wrong_values_name_the_key_and_the_expectation
    with_sandbox do |env|
      assert_file_error '"color" must be one of auto, always, never', env, "color: sometimes\n"
      assert_file_error '"theme" must be one of dark, light', env, "theme: solarized\n"
      assert_file_error '"editor" must be a string', env, "editor: [vim]\n"
      assert_file_error '"editor" must be a string', env, "editor: 3\n"
      assert_file_error "\"group\" must be a valid group name: #{Slipway::Names::RULE}", env, "group: Work\n"
      assert_file_error "\"group\" must be a valid group name: #{Slipway::Names::RULE}", env, "group: 7\n"
    end
  end

  def test_group_accepts_rfc_1123_labels_only
    with_sandbox do |env|
      write(env, "group: 3d-viewer\n")

      assert_equal '3d-viewer', load(env).group

      assert_file_error "\"group\" must be a valid group name: #{Slipway::Names::RULE}", env, "group: -lead\n"
      assert_file_error "\"group\" must be a valid group name: #{Slipway::Names::RULE}", env, "group: a.b\n"
      assert_file_error "\"group\" must be a valid group name: #{Slipway::Names::RULE}", env, "group: #{'a' * 64}\n"
    end
  end

  def test_yaml_errors_carry_the_path_once
    with_sandbox do |env|
      assert_file_error 'did not find expected node content while parsing a flow node at line 2 column 1',
                        env, "color: [\n"
      assert_file_error 'Tried to load unspecified class: Symbol', env, "color: :auto\n"
      assert_match(/\A#{Regexp.escape(config_path(env))}: Alias parsing was not enabled/,
                   error_for(env, "color: &c auto\ntheme: *c\n").message)
    end
  end

  def test_environment_values_are_validated_with_the_variable_as_prefix
    with_sandbox do |env|
      assert_settings_error 'SLIPWAY_COLOR: must be one of auto, always, never', env.merge('SLIPWAY_COLOR' => 'on')
      assert_settings_error 'SLIPWAY_THEME: must be one of dark, light', env.merge('SLIPWAY_THEME' => 'blue')
      assert_settings_error "SLIPWAY_GROUP: must be a valid group name: #{Slipway::Names::RULE}",
                            env.merge('SLIPWAY_GROUP' => 'My Group')
    end
  end

  def test_to_h_lists_string_keys_in_documented_order
    with_sandbox do |env|
      write(env, "theme: light\nnetworkTimeout: 30\n")

      assert_equal({ 'color' => 'auto', 'editor' => nil, 'group' => 'default', 'networkTimeout' => 30,
                     'parallel' => 4, 'protocols' => %w[ssh https], 'theme' => 'light' }, load(env).to_h)
      assert_equal Slipway::Settings::KEYS, load(env).to_h.keys
    end
  end

  def test_keys_and_documentation_cover_the_same_settings
    assert_equal %w[color editor group networkTimeout parallel protocols theme], Slipway::Settings::KEYS
    assert_equal Slipway::Settings::KEYS, Slipway::Settings::DOCUMENTATION.keys
    assert(Slipway::Settings::DOCUMENTATION.values.all? { it.is_a?(String) && it.end_with?('.') })
  end

  def test_error_is_a_slipway_error_with_exit_status_one
    error = Slipway::Settings::Error.new('boom')

    assert_kind_of Slipway::Error, error
    assert_equal 1, error.exit_status
    assert_nil error.hint
  end
end
