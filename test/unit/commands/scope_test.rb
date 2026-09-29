# frozen_string_literal: true

require 'test_helper'

class ScopeTest < Minitest::Test
  include CommandsHelper

  PROJECTS = Slipway::Resources.resolve('projects')
  GROUPS = Slipway::Resources.resolve('groups')

  def test_kind_resolves_type_words_and_rejects_unknown_ones
    with_scope do |scope|
      assert_equal PROJECTS, scope.kind('proj')
      assert_equal GROUPS, scope.kind('Group')
      error = assert_raises(Slipway::Error) { scope.kind('pods') }
      assert_equal 'unknown resource type "pods"', error.message
    end
  end

  def test_group_and_all_groups_come_from_the_flags_then_the_config
    with_scope do |scope|
      assert_equal 'default', scope.group
      refute_predicate scope, :all_groups?
    end
    with_scope(group: 'work', all_groups: true) do |scope|
      assert_equal 'work', scope.group
      assert_predicate scope, :all_groups?
    end
  end

  def test_select_without_names_lists_the_group_in_scope_filtered_by_the_selector
    with_scope(selector: 'lang=rust') do |scope, runtime|
      register_group(runtime, 'work')
      register(runtime, 'hldr', labels: { 'lang' => 'rust' })
      register(runtime, 'notes', labels: { 'lang' => 'md' })
      register(runtime, 'job', group: 'work', labels: { 'lang' => 'rust' })

      assert_equal %w[hldr], scope.select(PROJECTS, []).map(&:name)
    end
  end

  def test_select_spans_every_group_with_all_groups_and_ignores_the_group_for_groups
    with_scope(group: 'work', all_groups: true) do |scope, runtime|
      register_group(runtime, 'work')
      register(runtime, 'hldr')
      register(runtime, 'job', group: 'work')

      assert_equal([%w[default hldr], %w[work job]], scope.select(PROJECTS, []).map { [it.group, it.name] })
      assert_equal %w[default work], scope.select(GROUPS, []).map(&:name)
    end
  end

  def test_select_with_names_finds_each_one_in_the_group
    with_scope(group: 'work') do |scope, runtime|
      register_group(runtime, 'work')
      register(runtime, 'job', group: 'work')
      register(runtime, 'hldr')

      assert_equal %w[job], scope.select(PROJECTS, %w[job]).map(&:name)
      assert_equal %w[work default], scope.select(GROUPS, %w[work default]).map(&:name)
      error = assert_raises(Slipway::Store::NotFound) { scope.select(PROJECTS, %w[job hldr]) }
      assert_equal 'projects "hldr" not found', error.message
    end
  end

  def test_select_refuses_names_next_to_a_selector_or_all_groups
    with_scope(selector: 'lang=rust') do |scope|
      error = assert_raises(Slipway::CLI::UsageError) { scope.select(PROJECTS, %w[hldr]) }
      assert_equal 'name cannot be provided when a selector is specified', error.message
    end
    with_scope(all_groups: true) do |scope, runtime|
      register_group(runtime, 'work')
      error = assert_raises(Slipway::CLI::UsageError) { scope.select(PROJECTS, %w[hldr]) }
      assert_equal 'a resource cannot be retrieved by name across all groups', error.message
      assert_equal %w[work], scope.select(GROUPS, %w[work]).map(&:name)
    end
  end

  def test_a_blank_selector_matches_everything_and_a_malformed_one_is_a_usage_error
    with_scope(selector: '  ') do |scope, runtime|
      register(runtime, 'hldr')

      assert_equal %w[hldr], scope.select(PROJECTS, []).map(&:name)
    end
    with_scope(selector: 'a=b,') do |scope|
      assert_raises(Slipway::CLI::UsageError) { scope.select(PROJECTS, []) }
    end
  end

  def test_none_message_names_the_group_only_for_projects_in_one_group
    with_scope do |scope|
      assert_equal 'No resources found in default group.', scope.none_message(PROJECTS)
      assert_equal 'No resources found.', scope.none_message(GROUPS)
    end
    with_scope(group: 'work', all_groups: true) do |scope|
      assert_equal 'No resources found.', scope.none_message(PROJECTS)
    end
  end

  private

  def with_scope(group: nil, all_groups: nil, selector: nil)
    with_sandbox do |env|
      runtime = sandbox_runtime(env)
      yield Slipway::Commands::Scope.new(runtime, { group:, all_groups:, selector: }.freeze), runtime
    end
  end
end
