# frozen_string_literal: true

require 'json'
require 'test_helper'

# Facts two modules must agree on: theme roles, variable names, the config documentation and
# the shape a stored manifest takes when it is serialized.
class SeamsTest < Minitest::Test
  include Sandbox

  def test_every_state_role_exists_in_both_themes
    Slipway::CLI::Theme::NAMES.each do |name|
      roles = Slipway::CLI::Theme::PRESETS.fetch(name).keys

      Slipway::State::ROLES.each_value { assert_includes roles, it, name }
    end
  end

  def test_config_group_setting_applies_the_names_rule
    setting = Slipway::Config::SETTINGS.find { it.key == 'group' }

    %w[ok 3d-viewer -lead a.b Work].each do |value|
      assert_equal Slipway::Names.valid?(value), setting.valid.call(value), value
    end
  end

  def test_manpage_environment_lists_every_variable_the_code_reads
    expected = [Slipway::Paths::CONFIG_VARIABLE, Slipway::Paths::DATA_HOME_VARIABLE,
                *Slipway::Config::SETTINGS.map(&:variable), Slipway::CLI::Runner::DEBUG_VARIABLE,
                'NO_COLOR', *Slipway::CLI::Style::FORCE_VARIABLES,
                Slipway::Editor::VARIABLE, *Slipway::Editor::FALLBACK_VARIABLES,
                Slipway::Paths::XDG_CONFIG_HOME, Slipway::Paths::XDG_DATA_HOME]

    assert_equal expected.uniq.sort, Slipway::CLI::Manpage::DEFAULT_ENVIRONMENT.keys.sort
  end

  def test_runner_config_and_editor_read_the_same_variables
    variables = Slipway::Config::SETTINGS.to_h { [it.key, it.variable] }

    assert_equal variables.fetch('color'), Slipway::CLI::Runner::COLOR_VARIABLE
    assert_equal variables.fetch('theme'), Slipway::CLI::Runner::THEME_VARIABLE
    assert_equal variables.fetch('editor'), Slipway::Editor::VARIABLE
  end

  def test_config_documentation_covers_every_key_and_reads_as_the_man_page_prints_it
    assert_equal Slipway::Config::KEYS, Slipway::Config::DOCUMENTATION.keys
    assert_equal 'Group used when -n is not given. Default: default.', Slipway::Config::DOCUMENTATION.fetch('group')
    assert_equal 'Command line of the editor that slipway edit opens.', Slipway::Config::DOCUMENTATION.fetch('editor')
  end

  def test_an_untyped_color_flag_lets_the_config_file_decide
    fixture = FixtureRegistry.new
    fixture.run('get', 'projects')
    fixture.run('--color', 'get', 'projects')
    opts = fixture.calls.map(&:opts)

    assert_equal([nil, 'always'], opts.map { it[:color] })
    with_sandbox do |env|
      path = File.join(env['XDG_CONFIG_HOME'], 'slipway', 'config.yaml')
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, "color: never\n")
      config = Slipway::Config.load(Slipway::Paths.new(env), env:, flags: opts.first.slice(:color, :group))

      assert_equal %w[never default], [config.color, config.group]
    end
  end

  def test_store_manifests_serialize_as_kubectl_objects
    Dir.mktmpdir('slipway-seams-') do |root|
      store = Slipway::Store.new(root:, clock: -> { Time.utc(2026, 9, 29, 12, 0, 0) })
      project = store.create(Slipway::Project.new(name: 'hldr', path: '~/dev/hldr', labels: { 'lang' => 'rust' }))
      item = project.to_manifest.merge('status' => { 'state' => 'Clean' })

      assert_equal "#{Slipway::Manifest.dump(project)}status:\n  state: Clean\n",
                   Slipway::Output::Serializer.render('yaml', [item], single: true)
      assert_equal({ 'kind' => 'List', 'items' => [item] },
                   JSON.parse(Slipway::Output::Serializer.render('json', [item], single: false)))
      assert_equal project, Slipway::Manifest.parse_yaml(Slipway::Manifest.dump(project), source: 'dump')
    end
  end
end
