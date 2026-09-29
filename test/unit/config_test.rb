# frozen_string_literal: true

require 'test_helper'
require 'slipway/paths'
require 'slipway/config'

class ConfigTest < Minitest::Test
  include Sandbox

  def test_defaults_when_the_default_file_is_missing
    with_sandbox do |env|
      config = load(env)

      assert_equal %w[auto dark default], [config.color, config.theme, config.group]
      assert_nil config.editor
      assert_equal File.join(env['XDG_CONFIG_HOME'], 'slipway', 'config.yaml'), config.path
      refute_predicate config, :exists?
    end
  end

  def test_file_values_override_the_defaults
    with_sandbox do |env|
      write(env, "color: never\ntheme: light\neditor: code --wait\ngroup: work\n")
      config = load(env)

      assert_equal %w[never light], [config.color, config.theme]
      assert_equal 'code --wait', config.editor
      assert_equal 'work', config.group
      assert_predicate config, :exists?
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
      config = load(env)

      assert_equal %w[always dark vim home], [config.color, config.theme, config.editor, config.group]
    end
  end

  def test_empty_environment_values_count_as_unset
    with_sandbox do |env|
      write(env, "color: never\ngroup: work\n")
      config = load(env.merge('SLIPWAY_COLOR' => '', 'SLIPWAY_GROUP' => '', 'SLIPWAY_THEME' => ''))

      assert_equal %w[never dark work], [config.color, config.theme, config.group]
    end
  end

  def test_flags_outrank_the_environment
    with_sandbox do |env|
      write(env, "color: never\ngroup: work\n")
      config = load(env.merge('SLIPWAY_COLOR' => 'auto', 'SLIPWAY_GROUP' => 'home'),
                    flags: { color: 'always', group: 'lab', help: false })

      assert_equal 'always', config.color
      assert_equal 'lab', config.group
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

      assert_config_error "#{file}: no such file", env, config: file
      assert_config_error "#{file}: no such file", env.merge('SLIPWAY_CONFIG' => file)
    end
  end

  def test_unreadable_file_reports_the_system_error
    with_sandbox do |env|
      dir = File.join(env['HOME'], 'dir.yaml')
      Dir.mkdir(dir)

      assert_config_error "#{dir}: Is a directory", env, config: dir
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
      assert_file_error 'unknown key "colour" (known keys: color, editor, group, theme)', env, "colour: never\n"
      assert_file_error 'unknown key "1" (known keys: color, editor, group, theme)', env, "1: never\n"
    end
  end

  def test_wrong_values_name_the_key_and_the_expectation
    with_sandbox do |env|
      assert_file_error '"color" must be one of auto, always, never', env, "color: sometimes\n"
      assert_file_error '"theme" must be one of dark, light', env, "theme: solarized\n"
      assert_file_error '"editor" must be a string', env, "editor: [vim]\n"
      assert_file_error '"editor" must be a string', env, "editor: 3\n"
      assert_file_error '"group" must be a lowercase name of letters, digits and dashes', env, "group: Work\n"
      assert_file_error '"group" must be a lowercase name of letters, digits and dashes', env, "group: 7\n"
    end
  end

  def test_group_accepts_rfc_1123_labels_only
    with_sandbox do |env|
      write(env, "group: 3d-viewer\n")

      assert_equal '3d-viewer', load(env).group

      assert_file_error '"group" must be a lowercase name of letters, digits and dashes', env, "group: -lead\n"
      assert_file_error '"group" must be a lowercase name of letters, digits and dashes', env, "group: a.b\n"
      assert_file_error '"group" must be a lowercase name of letters, digits and dashes', env, "group: #{'a' * 64}\n"
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
      assert_config_error 'SLIPWAY_COLOR: must be one of auto, always, never', env.merge('SLIPWAY_COLOR' => 'on')
      assert_config_error 'SLIPWAY_THEME: must be one of dark, light', env.merge('SLIPWAY_THEME' => 'blue')
      assert_config_error 'SLIPWAY_GROUP: must be a lowercase name of letters, digits and dashes',
                          env.merge('SLIPWAY_GROUP' => 'My Group')
    end
  end

  def test_to_h_lists_string_keys_in_documented_order
    with_sandbox do |env|
      write(env, "theme: light\n")

      assert_equal({ 'color' => 'auto', 'editor' => nil, 'group' => 'default', 'theme' => 'light' }, load(env).to_h)
      assert_equal %w[color editor group theme], load(env).to_h.keys
    end
  end

  def test_keys_and_documentation_cover_the_same_settings
    assert_equal %w[color editor group theme], Slipway::Config::KEYS
    assert_equal Slipway::Config::KEYS, Slipway::Config::DOCUMENTATION.keys
    assert(Slipway::Config::DOCUMENTATION.values.all? { it.is_a?(String) && it.end_with?('.') })
  end

  def test_error_is_a_slipway_error_with_exit_status_one
    error = Slipway::Config::Error.new('boom')

    assert_kind_of Slipway::Error, error
    assert_equal 1, error.exit_status
    assert_nil error.hint
  end

  private

  def load(env, config: nil, flags: {})
    Slipway::Config.load(Slipway::Paths.new(env, config:), env:, flags:)
  end

  def config_path(env) = File.join(env['XDG_CONFIG_HOME'], 'slipway', 'config.yaml')

  def write(env, text)
    path = config_path(env)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, text)
  end

  def error_for(env, text)
    write(env, text)
    assert_raises(Slipway::Config::Error) { load(env) }
  end

  def assert_file_error(problem, env, text)
    assert_equal "#{config_path(env)}: #{problem}", error_for(env, text).message
  end

  def assert_config_error(message, env, config: nil)
    error = assert_raises(Slipway::Config::Error) { load(env, config:) }

    assert_equal message, error.message
  end
end
