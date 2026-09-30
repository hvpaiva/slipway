# frozen_string_literal: true

require 'test_helper'

class ExplainTest < Minitest::Test
  include CliHelper

  HINT = "See 'slipway explain --help' for usage.\n"

  GROUP = <<~TEXT
    KIND: Group

    DESCRIPTION:
        A namespace that holds projects, the way a Kubernetes namespace holds pods.
        Deleting a group removes the registrations of its projects.

    FIELDS:
      kind       <string> -required-
        The kind of resource the manifest describes. Must be Group.

      metadata   <Object> -required-
        Identifies the group: its name, its labels, and when it was created.

      spec       <Object>
        What the group is for.
  TEXT

  PROJECT_TREE = <<~TEXT
    FIELDS:
      kind                  <string> -required-
      metadata              <Object> -required-
        name                <string> -required-
        group               <string>
        labels              <map[string]string>
        creationTimestamp   <string>
      spec                  <Object> -required-
        path                <string> -required-
        description         <string>
        remote              <string>
        branch              <string>
        revision            <string>
        syncPolicy          <string>
        paused              <boolean>
  TEXT

  SYNC_POLICY = <<~TEXT
    KIND: Project

    FIELD: syncPolicy <string>

    DESCRIPTION:
        What sync may do to the repository: FastForward lets it fast-forward the
        checked-out branch, and FetchOnly lets it fetch only. Must be FastForward or
        FetchOnly. Defaults to FastForward.
  TEXT

  def test_a_type_prints_its_description_and_each_field_under_it
    assert_equal [0, GROUP, ''], explain('group')
  end

  def test_recursive_prints_every_field_as_a_tree_of_names_and_types
    status, out, err = explain('projects', '--recursive')

    assert_equal [0, ''], [status, err]
    assert_match(/\AKIND: Project\n\nDESCRIPTION:\n    A registered git repository:/, out)
    assert_equal PROJECT_TREE, out.split("\n\n").last
  end

  def test_a_field_prints_its_field_line_and_its_rule_and_default
    assert_equal [0, SYNC_POLICY, ''], explain('project.spec.syncPolicy')
    assert_equal [0, SYNC_POLICY, ''], explain('project.spec.syncPolicy', '--recursive')
  end

  def test_an_object_field_lists_the_fields_under_it
    status, out, = explain('project.metadata')
    names = out.scan(/^  (\S+) +<([^>]+)>/)

    assert_equal 0, status
    assert_match(/\AKIND: Project\n\nFIELD: metadata <Object> -required-\n\nDESCRIPTION:\n    Identifies/, out)
    assert_equal [%w[name string], %w[group string], ['labels', 'map[string]string'], %w[creationTimestamp string]],
                 names
  end

  def test_type_words_take_aliases_and_any_case_while_field_names_are_exact
    expected = explain('project.spec.paused')

    assert_equal expected, explain('proj.spec.paused')
    assert_equal expected, explain('PROJECTS.spec.paused')
    assert_equal [2, '', "error: field \"Paused\" does not exist\n#{HINT}"], explain('project.spec.Paused')
  end

  def test_a_field_that_does_not_exist_is_a_usage_error_naming_it
    assert_equal [2, '', "error: field \"nope\" does not exist\n#{HINT}"], explain('project.nope')
    assert_equal [2, '', "error: field \"x\" does not exist\n#{HINT}"], explain('project.spec.path.x')
    assert_equal [2, '', "error: field \"path\" does not exist\n#{HINT}"], explain('group.spec.path')
    assert_equal [2, '', "error: field \"\" does not exist\n#{HINT}"], explain('project.')
  end

  def test_an_unknown_type_is_refused_as_every_verb_refuses_it
    assert_equal [1, '', "error: unknown resource type \"pods\" (known types: projects, groups)\n"],
                 explain('pods.spec')
    assert_equal [1, '', "error: unknown resource type \"\" (known types: projects, groups)\n"], explain('')
  end

  def test_one_type_is_required
    assert_equal [2, '', "error: missing required argument \"TYPE\"\n#{HINT}"], explain
    assert_equal [2, '', "error: unexpected argument \"spec\"\n#{HINT}"], explain('project', 'spec')
  end

  def test_color_paints_the_labels_names_and_required_marks
    _, out, = explain('group', '--color=always')

    assert_includes out, "\e[96mKIND\e[0m: Group\n"
    assert_includes out, "  \e[96mkind\e[0m       <string> \e[31m-required-\e[0m\n"
    assert_includes out, "  \e[96mspec\e[0m       <Object>\n"
  end

  def test_completion_offers_the_types_then_the_fields_one_level_down_as_whole_paths
    assert_equal [[['projects', 'Registered git repositories'], ['groups', 'Namespaces that hold projects']], 6],
                 complete('')
    assert_equal [[['proj.kind', '<string>'], ['proj.metadata', '<Object>'], ['proj.spec', '<Object>']], 6],
                 complete('proj.')
    assert_equal [[['project.metadata', '<Object>']], 6], complete('project.me')
    assert_equal [%w[project.spec.path project.spec.paused], 4], names(complete('project.spec.pa'))
    assert_equal [%w[project.metadata.labels], 4], names(complete('project.metadata.l'))
  end

  def test_completion_offers_nothing_under_a_path_that_does_not_exist
    assert_equal [[], 4], complete('pods.')
    assert_equal [[], 4], complete('project.nope.')
    assert_equal [[], 4], complete('project.spec.path.')
  end

  private

  # A runtime would read the configuration; explain must work without one.
  def explain(*)
    registry = Slipway::Commands.registry(->(_context, _opts) { raise 'explain built a runtime' })
    run_cli('explain', *, registry:)
  end

  def complete(word)
    registry = Slipway::Commands.registry(->(_context, _opts) { raise 'unused' })
    Slipway::CLI::Completer.new(registry).complete(['explain', word])
  end

  def names((candidates, directive)) = [candidates.map(&:first), directive]
end
