# frozen_string_literal: true

require 'test_helper'

# `label`: every transition between labeled, unlabeled and not labeled, --overwrite, --list and the dry run.
class LabelTest < Minitest::Test
  include CommandsHelper

  PROJECTS = Slipway::Resources.resolve('projects')
  GROUPS = Slipway::Resources.resolve('groups')
  HINT = "See 'slipway label --help' for usage.\n"

  def test_a_new_label_is_labeled_and_the_same_value_again_is_not_labeled
    with_runtime do |runtime|
      register(runtime, 'hldr')

      assert_equal [0, "project/hldr labeled\n", ''], run_label('project', 'hldr', 'lang=rust', runtime:)
      assert_equal [0, "project/hldr not labeled\n", ''], run_label('project', 'hldr', 'lang=rust', runtime:)
      assert_equal({ 'lang' => 'rust' }, labels_of(runtime, 'hldr'))
    end
  end

  def test_a_different_value_needs_overwrite
    with_runtime do |runtime|
      register(runtime, 'hldr', labels: { 'lang' => 'rust' })

      assert_equal [1, '', "error: 'lang' already has a value (rust), and --overwrite is false\n"],
                   run_label('project', 'hldr', 'lang=go', runtime:)
      assert_equal({ 'lang' => 'rust' }, labels_of(runtime, 'hldr'))
      assert_equal [0, "project/hldr labeled\n", ''], run_label('project', 'hldr', 'lang=go', '--overwrite', runtime:)
      assert_equal({ 'lang' => 'go' }, labels_of(runtime, 'hldr'))
    end
  end

  def test_removals_alone_are_unlabeled_and_a_missing_key_is_a_no_op
    with_runtime do |runtime|
      register(runtime, 'hldr', labels: { 'lang' => 'rust', 'tier' => 'web' })

      assert_equal [0, "project/hldr unlabeled\n", ''], run_label('project', 'hldr', 'tier-', runtime:)
      assert_equal [0, "project/hldr not labeled\n", ''], run_label('project', 'hldr', 'tier-', runtime:)
      assert_equal({ 'lang' => 'rust' }, labels_of(runtime, 'hldr'))
    end
  end

  def test_a_set_together_with_a_removal_is_labeled
    with_runtime do |runtime|
      register(runtime, 'hldr', labels: { 'lang' => 'rust' })

      assert_equal [0, "project/hldr labeled\n", ''], run_label('project', 'hldr', 'lang-', 'app=web', runtime:)
      assert_equal({ 'app' => 'web' }, labels_of(runtime, 'hldr'))
    end
  end

  def test_groups_and_the_group_flag
    with_runtime do |runtime|
      register_group(runtime, 'work')
      register(runtime, 'api', group: 'work')
      register(runtime, 'api')

      assert_equal [0, "group/work labeled\n", ''], run_label('group', 'work', 'owner=me', runtime:)
      assert_equal [0, "project/api labeled\n", ''], run_label('project', 'api', 'lang=go', '-n', 'work', runtime:)
      assert_equal({ 'owner' => 'me' }, runtime.store.find(GROUPS, 'work', group: nil).labels)
      assert_equal [{ 'lang' => 'go' }, {}], [labels_of(runtime, 'api', group: 'work'), labels_of(runtime, 'api')]
    end
  end

  def test_list_prints_the_labels_one_per_line_and_writes_nothing
    with_runtime do |runtime|
      register(runtime, 'hldr', labels: { 'lang' => 'rust', 'app' => 'web' })
      register(runtime, 'bare')

      assert_equal [0, "app=web\nlang=rust\n", ''], run_label('project', 'hldr', '--list', runtime:)
      assert_equal [0, '', ''], run_label('project', 'bare', '--list', runtime:)
      assert_equal [0, "app=web\nlang=go\ntier=api\n", ''],
                   run_label('project', 'hldr', 'lang=go', 'tier=api', '--list', '--overwrite', runtime:)
      assert_equal({ 'app' => 'web', 'lang' => 'rust' }, labels_of(runtime, 'hldr'))
    end
  end

  def test_dry_run_prints_the_word_and_writes_nothing
    with_runtime do |runtime|
      register(runtime, 'hldr', labels: { 'lang' => 'rust' })
      labeled = run_label('project', 'hldr', 'app=web', '--dry-run', 'client', runtime:)
      unlabeled = run_label('project', 'hldr', 'lang-', '--dry-run=client', '--color', runtime:)
      unchanged = run_label('project', 'hldr', 'lang=rust', '--dry-run=client', '--color', runtime:)

      assert_equal [0, "project/hldr labeled (dry run)\n", ''], labeled
      assert_equal [0, "project/hldr \e[33munlabeled\e[0m \e[36m(dry run)\e[0m\n", ''], unlabeled
      assert_equal [0, "project/hldr \e[90;3mnot labeled\e[0m \e[36m(dry run)\e[0m\n", ''], unchanged
      assert_equal({ 'lang' => 'rust' }, labels_of(runtime, 'hldr'))
    end
  end

  def test_the_words_are_checked_before_the_resource_is_looked_up
    with_runtime do |runtime|
      assert_equal [2, '', "error: at least one label update is required\n#{HINT}"],
                   run_label('project', 'missing', runtime:)
      assert_equal [2, '', "error: invalid label \"bad\": expected KEY=VALUE or KEY-\n#{HINT}"],
                   run_label('project', 'missing', 'bad', runtime:)
      assert_equal [2, '', "error: label \"lang\" cannot be both set and removed\n#{HINT}"],
                   run_label('project', 'missing', 'lang=go', 'lang-', runtime:)
      assert_equal [1, '', "error: projects \"missing\" not found\n"],
                   run_label('project', 'missing', 'lang=go', runtime:)
      assert_equal [1, '', "error: groups \"missing\" not found\n"], run_label('groups', 'missing', '--list', runtime:)
    end
  end

  def test_help_and_arity
    with_runtime do |runtime|
      status, out, err = run_label('--help', runtime:)

      assert_equal [0, ''], [status, err]
      assert_includes out, "Update the labels on a resource.\n\n  *  A label key and value"
      assert_includes out, "Usage:\n  slipway label (TYPE NAME | TYPE/NAME) [KEY=VALUE|KEY-...] [flags]\n"
      assert_includes out, '      --overwrite'
      assert_equal [2, '', "error: missing required argument \"NAME\"\n#{HINT}"], run_label('project', runtime:)
      assert_equal [1, '', "error: unknown resource type \"pods\" (known types: projects, groups)\n"],
                   run_label('pods', 'x', 'a=b', runtime:)
    end
  end

  private

  def run_label(*argv, runtime:, **)
    run_commands('label', *argv, runtime:, commands: [Slipway::Commands::Label], **)
  end

  def labels_of(runtime, name, group: nil) = runtime.store.find(PROJECTS, name, group:).labels
end
