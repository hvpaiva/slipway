# frozen_string_literal: true

require 'json'
require 'test_helper'

class SeamsTest < Minitest::Test
  include Sandbox

  LIB = File.expand_path('../../lib', __dir__)
  # Universal variables every program reads; the man page does not list them.
  UNDOCUMENTED = %w[HOME PATH].freeze
  # Set for the git child process, to bound repository discovery and the transports a network
  # command may use, never read from the user.
  CHILD_ONLY = [Slipway::Git::Runner::CEILING_VARIABLE, Slipway::Git::Runner::PROTOCOL_VARIABLE].freeze
  # Upper case, with the odd lower-case suffix such as LESS_TERMCAP_md.
  NAME = /[A-Z][A-Za-z0-9_]+/
  # env['X'], @env.fetch('X'), env.fetch 'X', ENV.key?('X'), context.env['X'], ...
  READ = /\b(?:env|ENV)(?:\[|\.(?:fetch|key\?|include\?|has_key\?|member\?)\(?)\s*['"](#{NAME})['"]/
  # FOO_VARIABLE = 'X' or FOO_VARIABLES = %w[X Y], and the bare VARIABLE constant.
  NAMED = /^\s*(?:[A-Z0-9_]+_)?VARIABLES?\s*=\s*(?:['"](#{NAME})['"]|%w\[([^\]]*)\])/

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
    expected = (variables_read_by_lib + Slipway::Config::SETTINGS.map(&:variable)).uniq - UNDOCUMENTED - CHILD_ONLY

    assert_equal expected.sort, Slipway::CLI::Manpage::DEFAULT_ENVIRONMENT.keys.sort
    assert_operator expected.size, :>, 15
  end

  def test_the_variable_scan_finds_reads_and_named_constants
    source = <<~RUBY
      NAME_VARIABLE = 'A_ONE'
      OTHER_VARIABLES = %w[B_TWO C_THREE].freeze
      XDG_DATA_HOME_VARIABLE = 'D_FOUR'
      STATUS = 'STATUS'
      HEADER = 'NAME'
      x = env['E_five'] || @env.fetch("F_SIX", '') || ENV['G_SEVEN'] || context.env[name]
      y = env.key?('H_EIGHT') || env.fetch 'I_NINE', nil
    RUBY

    assert_equal %w[A_ONE B_TWO C_THREE D_FOUR E_five F_SIX G_SEVEN H_EIGHT I_NINE], variables_in(source).sort
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

  private

  def variables_read_by_lib
    Dir.glob('**/*.rb', base: LIB).flat_map { variables_in(File.read(File.join(LIB, it))) }.uniq
  end

  def variables_in(source)
    [*source.scan(READ).flatten, *source.scan(NAMED).flat_map { |single, list| single ? [single] : list.split }]
  end
end
