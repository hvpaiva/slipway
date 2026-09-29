# frozen_string_literal: true

require 'test_helper'

class LabelIntegrationTest < Minitest::Test
  include IntegrationHelper

  def seed_clean(env)
    seed(env, manifest('Project', 'clean', path: repo(env, 'clean'), labels: { 'lang' => 'rust' }))
  end

  def test_sets_a_new_label_and_lists_the_result
    with_home do |env|
      seed_clean(env)
      status, out, err = slipway('label', 'project', 'clean', 'tier=web', env:)

      assert_equal [0, "project/clean labeled\n", ''], [status, out, err]
      assert_equal "lang=rust\ntier=web\n", slipway!('label', 'project', 'clean', '--list', env:)
      assert_equal 'lang=rust,tier=web', table(slipway!('get', 'projects', '--show-labels', env:)).last.last
    end
  end

  def test_overwriting_needs_the_flag
    with_home do |env|
      seed_clean(env)
      status, out, err = slipway('label', 'project', 'clean', 'lang=go', env:)

      assert_equal [1, '', "error: 'lang' already has a value (rust), and --overwrite is false\n"], [status, out, err]
      assert_equal [0, "project/clean labeled\n", ''],
                   slipway('label', 'project', 'clean', 'lang=go', '--overwrite', env:)
      assert_equal [0, "project/clean not labeled\n", ''], slipway('label', 'project', 'clean', 'lang=go', env:)
    end
  end

  def test_a_trailing_dash_removes_a_label
    with_home do |env|
      seed_clean(env)
      slipway!('label', 'project', 'clean', 'tier=web', env:)

      assert_equal [0, "project/clean unlabeled\n", ''], slipway('label', 'project', 'clean', 'tier-', env:)
      assert_equal [0, "project/clean not labeled\n", ''], slipway('label', 'project', 'clean', 'tier-', env:)
      assert_equal "lang=rust\n", slipway!('label', 'project', 'clean', '--list', env:)
    end
  end

  def test_dry_run_reports_without_writing
    with_home do |env|
      seed_clean(env)
      status, out, err = slipway('label', 'project', 'clean', 'a=b', '--dry-run=client', env:)

      assert_equal [0, "project/clean labeled (dry run)\n", ''], [status, out, err]
      assert_equal "lang=rust\n", slipway!('label', 'project', 'clean', '--list', env:)
    end
  end

  def test_groups_take_labels_too
    with_home do |env|
      seed(env, manifest('Group', 'work'))

      assert_equal [0, "group/work labeled\n", ''], slipway('label', 'group', 'work', 'team=platform', env:)
      assert_equal "team=platform\n", slipway!('label', 'group', 'work', '--list', env:)
    end
  end

  def test_usage_and_runtime_errors
    with_home do |env|
      seed_clean(env)
      hint = "See 'slipway label --help' for usage.\n"

      assert_equal [2, '', "error: at least one label update is required\n#{hint}"],
                   slipway('label', 'project', 'clean', env:)
      assert_equal [2, '', 'error: "bad key" is not a valid label key: letters, digits, dashes, underscores and ' \
                           'dots, starting and ending with a letter or digit, at most 63 characters, with an ' \
                           "optional DNS subdomain prefix and a slash\n#{hint}"],
                   slipway('label', 'project', 'clean', 'bad key=1', env:)
      assert_equal [1, '', "error: projects \"nothere\" not found\n"],
                   slipway('label', 'project', 'nothere', 'a=b', env:)
    end
  end
end
