# frozen_string_literal: true

require 'json'
require 'test_helper'

class FieldSelectorIntegrationTest < Minitest::Test
  include IntegrationHelper
  include GetRegistry

  UNSUPPORTED = <<~TEXT
    error: invalid field selector "spec.remote=x": field label not supported: "spec.remote"
    See 'slipway get --help' for usage.
  TEXT

  def test_get_lists_the_projects_whose_state_is_not_clean_in_every_group
    with_home do |env|
      registry(env)
      status, out, err = slipway('get', 'projects', '-A', '--field-selector', 'status.state!=Clean', env:)

      assert_equal [0, ''], [status, err]
      assert_table [%w[GROUP NAME BRANCH STATUS FETCHED AGE],
                    ['default', 'dirty', 'main', 'Dirty', '<never>', :age],
                    ['default', 'gone', '<none>', 'Missing', '<none>', :age],
                    ['default', 'plain', '<none>', 'NotARepo', '<none>', :age],
                    ['work', 'ahead', 'main', 'Ahead', '<never>', :age],
                    ['work', 'detached', '(detached)', 'Detached', '<never>', :age]], out
    end
  end

  def test_fields_combine_with_each_other_and_with_a_label_selector
    with_home do |env|
      registry(env)

      assert_equal "project/ahead\n", slipway!('get', 'projects', '-A', '-o', 'name', '--field-selector',
                                               'status.branch=main,metadata.group=work', env:)
      assert_equal "project/clean\n", slipway!('get', 'projects', '-o', 'name', '-l', 'lang', '--field-selector',
                                               'status.state=Clean', env:)
    end
  end

  # The fixture's origin is a local path, which git reaches over the file transport.
  def test_last_fetch_selects_on_the_time_json_prints_or_never
    with_home do |env|
      env = env.merge('SLIPWAY_PROTOCOLS' => 'ssh:https:file')
      seed(env, manifest('Project', 'clean', path: repo(env, 'clean')),
           manifest('Project', 'synced', path: repo(env, 'synced', 'synced')))
      slipway!('fetch', 'synced', env:)
      fetched = JSON.parse(slipway!('get', 'project', 'synced', '-o', 'json', env:)).dig('status', 'lastFetch')

      assert_equal "project/clean\n",
                   slipway!('get', 'projects', '-o', 'name', '--field-selector', 'status.lastFetch=never', env:)
      assert_equal "project/synced\n",
                   slipway!('get', 'projects', '-o', 'name', '--field-selector', "status.lastFetch=#{fetched}", env:)
    end
  end

  def test_describe_shows_only_the_objects_that_match
    with_home do |env|
      registry(env)
      _, projects, = slipway('describe', 'projects', '--field-selector', 'spec.path=~/dev/plain', env:)
      _, groups, = slipway('describe', 'groups', '--field-selector', 'metadata.name=work', env:)

      assert_equal %w[plain], projects.scan(/^Name: +(\S+)$/).flatten
      assert_equal %w[work], groups.scan(/^Name: +(\S+)$/).flatten
    end
  end

  def test_nothing_matched_and_an_unsupported_field
    with_home do |env|
      registry(env)

      assert_equal [0, '', "No resources found in default group.\n"],
                   slipway('get', 'projects', '--field-selector', 'status.state=Behind', env:)
      assert_equal [2, '', UNSUPPORTED], slipway('get', 'projects', '--field-selector', 'spec.remote=x', env:)
    end
  end

  def test_the_flag_completes_with_its_description
    with_home do |env|
      status, out, err = slipway('__complete', 'describe', 'projects', '--field', env:)

      assert_equal [0, ''], [status, err]
      assert_equal "--field-selector\t#{Slipway::Commands::Options::FIELD_SELECTOR.description}\n:4\n", out
    end
  end
end
