# frozen_string_literal: true

require 'test_helper'

class ScopeTest < Minitest::Test
  include CommandsHelper

  PROJECTS = Slipway::Resources::PROJECTS
  GROUPS = Slipway::Resources::GROUPS

  def test_kind_resolves_type_words_and_rejects_unknown_ones_naming_the_known_types
    with_scope do |scope|
      assert_equal PROJECTS, scope.kind('proj')
      assert_equal GROUPS, scope.kind('Group')
      error = assert_raises(Slipway::Error) { scope.kind('pods') }
      assert_equal 'unknown resource type "pods" (known types: projects, groups)', error.message
      assert_equal 1, error.exit_status
    end
  end

  def test_targets_accept_type_then_names_and_the_type_slash_name_form
    with_scope do |scope|
      assert_equal [PROJECTS, []], scope.targets(%w[projects])
      assert_equal [PROJECTS, %w[a b]], scope.targets(%w[project a b])
      assert_equal [PROJECTS, %w[a b]], scope.targets(%w[project/a proj/b])
      assert_equal [GROUPS, %w[work]], scope.targets(%w[group/work])
    end
  end

  def test_targets_refuse_mixed_kinds_mixed_forms_and_invalid_names_as_usage_errors
    with_scope do |scope|
      mixed = assert_raises(Slipway::CLI::UsageError) { scope.targets(%w[project/a group/b]) }
      forms = assert_raises(Slipway::CLI::UsageError) { scope.targets(%w[project/a b]) }
      bad = assert_raises(Slipway::CLI::UsageError) { scope.targets(%w[project Bad_Name]) }

      assert_equal 'all resources must share one type', mixed.message
      assert_equal 'a name in TYPE/NAME form cannot be combined with a bare name', forms.message
      assert_equal "\"Bad_Name\" is not a valid project name: #{Slipway::Names::RULE}", bad.message
    end
  end

  def test_target_wants_exactly_one_name
    with_scope do |scope|
      assert_equal [GROUPS, 'work'], scope.target(%w[group work])
      assert_equal [PROJECTS, 'a'], scope.target(%w[project/a])
      missing = assert_raises(Slipway::CLI::UsageError) { scope.target(%w[project]) }
      extra = assert_raises(Slipway::CLI::UsageError) { scope.target(%w[project/a project/b]) }

      assert_equal 'missing required argument "NAME"', missing.message
      assert_equal 'unexpected argument "b"', extra.message
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

  def test_an_invalid_group_flag_is_a_usage_error
    with_scope(group: 'Nope') do |scope|
      error = assert_raises(Slipway::CLI::UsageError) { scope.group }

      assert_equal "\"Nope\" is not a valid group name: #{Slipway::Names::RULE}", error.message
    end
  end

  def test_select_without_names_lists_the_group_in_scope_filtered_by_the_selector
    with_scope(selector: 'lang=rust') do |scope, runtime|
      register_group(runtime, 'work')
      register(runtime, 'hldr', labels: { 'lang' => 'rust' })
      register(runtime, 'notes', labels: { 'lang' => 'md' })
      register(runtime, 'job', group: 'work', labels: { 'lang' => 'rust' })

      assert_equal %w[hldr], selected(scope, PROJECTS, []).map(&:name)
    end
  end

  def test_select_spans_every_group_with_all_groups_and_ignores_the_group_for_groups
    with_scope(group: 'work', all_groups: true) do |scope, runtime|
      register_group(runtime, 'work')
      register(runtime, 'hldr')
      register(runtime, 'job', group: 'work')

      assert_equal([%w[default hldr], %w[work job]], selected(scope, PROJECTS, []).map { [it.group, it.name] })
      assert_equal %w[default work], selected(scope, GROUPS, []).map(&:name)
    end
  end

  def test_select_with_names_finds_each_one_in_the_group
    with_scope(group: 'work') do |scope, runtime|
      register_group(runtime, 'work')
      register(runtime, 'job', group: 'work')
      register(runtime, 'hldr')

      assert_equal %w[job], selected(scope, PROJECTS, %w[job]).map(&:name)
      assert_equal %w[work default], selected(scope, GROUPS, %w[work default]).map(&:name)
    end
  end

  def test_select_yields_the_names_found_then_raises_one_problem_per_missing_name
    with_scope do |scope, runtime|
      register(runtime, 'hldr')
      yielded = []
      error = assert_raises(Slipway::Error) { scope.select(PROJECTS, %w[nope hldr gone]) { yielded << it } }

      assert_equal [%w[hldr]], yielded.map { |resources| resources.map(&:name) }.to_a
      assert_equal ['projects "nope" not found', 'projects "gone" not found'], error.problems
      only_missing = assert_raises(Slipway::Error) { scope.select(PROJECTS, %w[nope]) { flunk 'nothing to show' } }
      assert_equal ['projects "nope" not found'], only_missing.problems
    end
  end

  def test_select_refuses_names_next_to_a_selector_or_all_groups
    with_scope(selector: 'lang=rust') do |scope|
      error = assert_raises(Slipway::CLI::UsageError) { selected(scope, PROJECTS, %w[hldr]) }
      assert_equal 'name cannot be provided when a selector is specified', error.message
    end
    with_scope(all_groups: true) do |scope, runtime|
      register_group(runtime, 'work')
      error = assert_raises(Slipway::CLI::UsageError) { selected(scope, PROJECTS, %w[hldr]) }
      assert_equal 'a resource cannot be retrieved by name across all groups', error.message
      assert_equal %w[work], selected(scope, GROUPS, %w[work]).map(&:name)
    end
  end

  def test_a_blank_selector_matches_everything_and_a_malformed_one_is_a_usage_error
    with_scope(selector: '  ') do |scope, runtime|
      register(runtime, 'hldr')

      assert_equal %w[hldr], selected(scope, PROJECTS, []).map(&:name)
    end
    with_scope(selector: 'a=b,') do |scope|
      assert_raises(Slipway::CLI::UsageError) { selected(scope, PROJECTS, []) }
    end
  end

  def test_a_listing_warns_about_a_manifest_it_cannot_read_and_shows_the_rest
    with_scope do |scope, runtime, context|
      register(runtime, 'hldr')
      stray = File.join(runtime.store.root, 'projects', 'default', 'stray.yaml')
      File.write(stray, "kind: Project\nmetadata:\n  name: other\nspec:\n  path: /x\n")

      assert_equal %w[hldr], selected(scope, PROJECTS, []).map(&:name)
      assert_equal "warning: #{stray}: describes project \"other\", which does not belong at this path\n",
                   context.err.string
    end
  end

  def test_a_warning_about_a_manifest_makes_its_control_characters_visible
    with_scope do |scope, runtime, context|
      FileUtils.mkdir_p(File.join(runtime.store.root, 'projects', 'default'))
      stray = File.join(runtime.store.root, 'projects', 'default', "\e]0;x\a.yaml")
      File.write(stray, "kind: Project\nmetadata:\n  name: other\nspec:\n  path: /x\n")

      assert_empty selected(scope, PROJECTS, [])
      assert_equal "warning: #{File.dirname(stray)}/^[]0;x^G.yaml: describes project \"other\", which does not " \
                   "belong at this path\n", context.err.string
    end
  end

  def test_report_none_names_the_group_only_for_projects_in_one_group
    with_scope do |scope, _runtime, context|
      scope.report_none(PROJECTS)
      scope.report_none(GROUPS)

      assert_equal "No resources found in default group.\nNo resources found.\n", context.err.string
    end
    with_scope(group: 'work', all_groups: true) do |scope, _runtime, context|
      scope.report_none(PROJECTS)

      assert_equal "No resources found.\n", context.err.string
    end
  end

  def test_report_none_paints_the_notice_muted_with_the_group_in_the_string_role
    with_scope(color: 'always') do |scope, _runtime, context|
      scope.report_none(PROJECTS)

      assert_equal "\e[90;3mNo resources found in \e[0m\e[93mdefault\e[0m\e[90;3m group.\e[0m\n", context.err.string
    end
  end

  private

  def selected(scope, kind, names)
    result = nil
    scope.select(kind, names) { result = it }
    result
  end

  def with_scope(group: nil, all_groups: nil, selector: nil, color: nil)
    with_sandbox do |env|
      runtime = sandbox_runtime(env)
      context = Slipway::CLI::Context.new(out: StringIO.new, err: StringIO.new, env:)
      context = context.with_color(color) if color
      yield Slipway::Commands::Scope.new(runtime, context, { group:, all_groups:, selector: }.freeze), runtime, context
    end
  end
end
