# frozen_string_literal: true

require 'test_helper'

class ExplainIntegrationTest < Minitest::Test
  include IntegrationHelper

  PAUSED = <<~TEXT
    KIND: Project

    FIELD: paused <boolean>

    DESCRIPTION:
        When true, fetch and sync leave the project alone: they report it as paused
        and run no git command there. rollout pause sets it and rollout resume
        removes it. Defaults to false.
  TEXT

  def test_explain_prints_a_field_and_refuses_one_that_does_not_exist
    with_home do |env|
      assert_equal [0, PAUSED, ''], slipway('explain', 'proj.spec.paused', env:)
      assert_equal [2, '', "error: field \"pause\" does not exist\nSee 'slipway explain --help' for usage.\n"],
                   slipway('explain', 'project.spec.pause', env:)
    end
  end

  def test_explain_reads_no_configuration_file
    with_home do |env|
      config = File.join(env['XDG_CONFIG_HOME'], 'slipway', 'config.yaml')
      FileUtils.mkdir_p(File.dirname(config))
      File.write(config, "colour: always\n")

      assert_equal 1, slipway('get', 'projects', env:).first
      assert_equal [0, PAUSED, ''], slipway('explain', 'project.spec.paused', env:)
    end
  end

  def test_completion_offers_field_paths_level_by_level_with_no_space_after_one_that_goes_on
    with_home do |env|
      assert_equal [0, "proj.kind\t<string>\nproj.metadata\t<Object>\nproj.spec\t<Object>\n:6\n", ''],
                   slipway('__complete', 'explain', 'proj.', env:)
      assert_equal [0, "project.spec.syncPolicy\t<string>\n:4\n", ''],
                   slipway('__complete', 'explain', 'project.spec.sync', env:)
      assert_equal [0, ":4\n", ''], slipway('__complete', 'explain', 'project', '', env:)
    end
  end
end
