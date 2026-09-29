# frozen_string_literal: true

require 'test_helper'
require_relative 'get_registry'

class GetIntegrationTest < Minitest::Test
  include IntegrationHelper
  include GetRegistry

  def test_table_lists_the_current_group
    with_home do |env|
      registry(env)
      status, out, err = slipway('get', 'projects', env:)

      assert_equal [0, ''], [status, err]
      assert_table [%w[NAME BRANCH STATUS AGE],
                    ['clean', 'main', 'Clean', :age],
                    ['dirty', 'main', 'Dirty', :age],
                    ['gone', '<none>', 'Missing', :age],
                    ['plain', '<none>', 'NotARepo', :age]], out
    end
  end

  def test_wide_adds_path_head_and_last_commit
    with_home do |env|
      registry(env)
      status, out, err = slipway('get', 'projects', '-o', 'wide', env:)

      assert_equal [0, ''], [status, err]
      assert_table [%w[NAME BRANCH STATUS AGE PATH HEAD LAST-COMMIT],
                    ['clean', 'main', 'Clean', :age, '~/dev/clean', HEAD, :age],
                    ['dirty', 'main', 'Dirty', :age, '~/dev/dirty', HEAD, :age],
                    ['gone', '<none>', 'Missing', :age, '~/dev/gone', '<none>', '<none>'],
                    ['plain', '<none>', 'NotARepo', :age, '~/dev/plain', '<none>', '<none>']], out
    end
  end

  def test_show_labels_appends_the_labels_column
    with_home do |env|
      registry(env)
      _, out, = slipway('get', 'projects', '--show-labels', env:)

      assert_table [%w[NAME BRANCH STATUS AGE LABELS],
                    ['clean', 'main', 'Clean', :age, 'lang=rust'],
                    ['dirty', 'main', 'Dirty', :age, 'lang=go'],
                    ['gone', '<none>', 'Missing', :age, '<none>'],
                    ['plain', '<none>', 'NotARepo', :age, '<none>']], out
    end
  end

  def test_all_groups_prepends_the_group_column
    with_home do |env|
      registry(env)
      _, out, = slipway('get', 'projects', '-A', env:)

      assert_table [%w[GROUP NAME BRANCH STATUS AGE],
                    ['default', 'clean', 'main', 'Clean', :age],
                    ['default', 'dirty', 'main', 'Dirty', :age],
                    ['default', 'gone', '<none>', 'Missing', :age],
                    ['default', 'plain', '<none>', 'NotARepo', :age],
                    ['work', 'ahead', 'main', 'Ahead', :age],
                    ['work', 'detached', '(detached)', 'Detached', :age]], out
    end
  end

  def test_every_column_flag_together_without_headers
    with_home do |env|
      registry(env)
      _, out, = slipway('get', 'projects', '-A', '-o', 'wide', '--show-labels', '--no-headers', env:)

      assert_table [['default', 'clean', 'main', 'Clean', :age, '~/dev/clean', HEAD, :age, 'lang=rust'],
                    ['default', 'dirty', 'main', 'Dirty', :age, '~/dev/dirty', HEAD, :age, 'lang=go'],
                    ['default', 'gone', '<none>', 'Missing', :age, '~/dev/gone', '<none>', '<none>', '<none>'],
                    ['default', 'plain', '<none>', 'NotARepo', :age, '~/dev/plain', '<none>', '<none>', '<none>'],
                    ['work', 'ahead', 'main', 'Ahead', :age, '~/dev/ahead', '0182104', :age, 'lang=rust,tier=api'],
                    ['work', 'detached', '(detached)', 'Detached', :age, '~/dev/detached', HEAD, :age, '<none>']],
                   out
    end
  end

  def test_selectors_filter_by_label
    with_home do |env|
      registry(env)
      _, rust, = slipway('get', 'projects', '-l', 'lang=rust', '-A', env:)
      _, go, = slipway('get', 'projects', '-l', 'lang in (go),tier!=api', env:)
      _, no_lang, err = slipway('get', 'projects', '-l', '!lang', env:)

      assert_table [%w[GROUP NAME BRANCH STATUS AGE], ['default', 'clean', 'main', 'Clean', :age],
                    ['work', 'ahead', 'main', 'Ahead', :age]], rust
      assert_table [%w[NAME BRANCH STATUS AGE], ['dirty', 'main', 'Dirty', :age]], go
      assert_table [%w[NAME BRANCH STATUS AGE], ['gone', '<none>', 'Missing', :age],
                    ['plain', '<none>', 'NotARepo', :age]], no_lang
      assert_empty err
    end
  end

  def test_nothing_selected_is_a_notice_on_stderr
    with_home do |env|
      registry(env)

      assert_equal [0, '', "No resources found in empty group.\n"], slipway('get', 'projects', '-n', 'empty', env:)
      assert_equal [0, '', "No resources found.\n"], slipway('get', 'groups', '-l', 'x=y', env:)
      assert_equal [0, '', "No resources found.\n"], slipway('get', 'projects', '-A', '-l', 'lang=c', env:)
      empty = env.merge('XDG_DATA_HOME' => File.join(env['HOME'], 'empty'))

      assert_equal [0, '', "No resources found in default group.\n"], slipway('get', 'projects', env: empty)
    end
  end

  def test_an_unknown_name_or_type_is_a_runtime_error
    with_home do |env|
      registry(env)

      assert_equal [1, '', "error: projects \"nothere\" not found\n"], slipway('get', 'project', 'nothere', env:)
      assert_equal [1, '', "error: groups \"nothere\" not found\n"], slipway('get', 'group', 'nothere', env:)
      assert_equal [1, '', "error: unknown resource type \"pods\"\n"], slipway('get', 'pods', env:)
    end
  end

  def test_names_cannot_be_combined_with_a_selector_or_all_groups
    with_home do |env|
      registry(env)
      hint = "See 'slipway get --help' for usage.\n"

      assert_equal [2, '', "error: name cannot be provided when a selector is specified\n#{hint}"],
                   slipway('get', 'project', 'clean', '-l', 'a=b', env:)
      assert_equal [2, '', "error: a resource cannot be retrieved by name across all groups\n#{hint}"],
                   slipway('get', 'project', 'clean', '-A', env:)
    end
  end

  def test_usage_errors_exit_2_with_a_hint
    with_home do |env|
      hint = "See 'slipway get --help' for usage.\n"

      assert_equal [2, '', "error: missing required argument \"TYPE\"\n#{hint}"], slipway('get', env:)
      assert_equal [2, '', 'error: invalid argument "xml" for "-o, --output FORMAT": must be one of table, ' \
                           "wide, json, yaml, name\n#{hint}"], slipway('get', 'projects', '-o', 'xml', env:)
      assert_equal [2, '', "error: unknown flag: --bogus\n#{hint}"], slipway('get', 'projects', '--bogus', env:)
      assert_equal [2, '', "error: unknown flag: -x\n#{hint}"], slipway('get', 'projects', '-x', env:)
    end
  end

  def test_the_group_comes_from_the_flag_the_variable_or_the_file
    with_home do |env|
      registry(env)
      write_config(env, "group: work\n")

      assert_equal "project/ahead\nproject/detached\n", slipway!('get', 'projects', '-o', 'name', env:)
      assert_equal "project/clean\nproject/dirty\nproject/gone\nproject/plain\n",
                   slipway!('get', 'projects', '-o', 'name', env: env.merge('SLIPWAY_GROUP' => 'default'))
      assert_equal "project/ahead\nproject/detached\n",
                   slipway!('get', 'projects', '-o', 'name', '-n', 'work', env: env.merge('SLIPWAY_GROUP' => 'default'))
    end
  end
end
