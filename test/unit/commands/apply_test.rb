# frozen_string_literal: true

require 'test_helper'
require 'stringio'

class ApplyTest < Minitest::Test
  include CommandsHelper

  PROJECTS = Slipway::Resources.resolve('projects')
  GROUPS = Slipway::Resources.resolve('groups')
  HLDR = "kind: Project\nmetadata:\n  name: hldr\nspec:\n  path: ~/dev/hldr\n"
  WORK = "kind: Group\nmetadata:\n  name: work\nspec:\n  description: Day job\n"
  API = "kind: Project\nmetadata:\n  name: api\n  group: work\nspec:\n  path: ~/work/api\n"

  def test_a_manifest_is_created_then_unchanged_then_configured
    with_runtime do |runtime, home|
      file = write(home, 'hldr.yaml', HLDR)

      assert_equal [0, "project/hldr created\n", ''], run_apply('-f', file, runtime:)
      assert_equal [0, "project/hldr unchanged\n", ''], run_apply('-f', file, runtime:)
      write(home, 'hldr.yaml', "#{HLDR}  description: Site\n")

      assert_equal [0, "project/hldr configured\n", ''], run_apply('--filename', file, runtime:)
      project = runtime.store.find(PROJECTS, 'hldr', group: nil)

      assert_equal ['Site', CREATED], [project.description, project.created_at]
    end
  end

  def test_the_group_comes_from_the_manifest_then_the_flag_then_default
    with_runtime do |runtime, home|
      register_group(runtime, 'work')
      register_group(runtime, 'home')
      api = write(home, 'api.yaml', API)
      hldr = write(home, 'hldr.yaml', HLDR)

      assert_equal "project/api created\n", run_apply('-f', api, '-n', 'home', runtime:)[1]
      assert_equal "project/hldr created\n", run_apply('-f', hldr, '-n', 'home', runtime:)[1]
      assert_equal "project/hldr created\n", run_apply('-f', hldr, runtime:)[1]
      placed = runtime.store.list(PROJECTS).map { [it.name, it.group] }

      assert_equal [%w[hldr default], %w[hldr home], %w[api work]], placed
    end
  end

  def test_a_directory_applies_its_yaml_and_yml_files_sorted_without_descending
    with_runtime do |runtime, home|
      dir = File.join(home, 'manifests')
      write(dir, 'b.yaml', API)
      write(dir, 'a.yml', WORK)
      write(dir, 'c.txt', HLDR)
      write(File.join(dir, 'sub'), 'd.yaml', HLDR)

      assert_equal [0, "group/work created\nproject/api created\n", ''], run_apply('-f', dir, runtime:)
      assert_equal %w[api], runtime.store.names(PROJECTS)
    end
  end

  def test_a_dash_reads_the_manifests_from_stdin
    with_runtime do |runtime|
      result = with_stdin("#{WORK}---\n#{API}") { run_apply('-f', '-', runtime:) }

      assert_equal [0, "group/work created\nproject/api created\n", ''], result
      broken = "---\n#{WORK}---\nkind: Project\nmetadata:\n  name: x\n"

      assert_equal [1, "group/work unchanged\n", "error: STDIN:2: \"spec.path\" is required\n"],
                   with_stdin(broken) { run_apply('-f', '-', runtime:) }
    end
  end

  def test_documents_are_applied_in_order_so_a_group_may_precede_its_projects
    with_runtime do |runtime, home|
      file = write(home, 'all.yaml', "#{WORK}---\n#{API}---\n#{HLDR}")

      assert_equal [0, "group/work created\nproject/api created\nproject/hldr created\n", ''],
                   run_apply('-f', file, runtime:)
      assert_equal [0, "group/work unchanged\nproject/api unchanged\nproject/hldr unchanged\n", ''],
                   run_apply('-f', file, runtime:)
    end
  end

  def test_a_list_applies_each_item_and_names_a_failing_one_by_its_position
    with_runtime do |runtime, home|
      items = [WORK, API, "kind: Project\nmetadata:\n  name: x\n"].map { Psych.safe_load(it) }
      file = write(home, 'list.yaml', Slipway::Yaml.dump({ 'kind' => 'List', 'items' => items }))

      assert_equal [1, "group/work created\nproject/api created\n", "error: #{file}:3: \"spec.path\" is required\n"],
                   run_apply('-f', file, runtime:)
    end
  end

  def test_errors_are_collected_and_printed_after_the_successes
    with_runtime do |runtime, home|
      broken = write(home, 'broken.yaml', "kind: Project\nmetadata:\n  name: x\n")
      orphan = write(home, 'orphan.yaml', API)
      syntax = write(home, 'syntax.yaml', "kind: [\n")
      good = write(home, 'good.yaml', HLDR)
      missing = File.join(home, 'missing.yaml')
      status, out, err = run_apply('-f', broken, '-f', orphan, '-f', syntax, '-f', missing, '-f', good, runtime:)

      assert_equal [1, "project/hldr created\n"], [status, out]
      assert_equal "error: #{broken}: \"spec.path\" is required\n" \
                   "error: #{orphan}: groups \"work\" not found\n" \
                   "error: #{syntax}: did not find expected node content at line 2, column 1\n" \
                   "error: #{missing}: no such file\n", err
    end
  end

  def test_a_failing_document_names_its_index_and_the_others_still_apply
    with_runtime do |runtime, home|
      file = write(home, 'mixed.yaml', "#{HLDR}---\nkind: Pod\n---\n#{WORK}")
      status, out, err = run_apply('-f', file, runtime:)

      assert_equal [1, "project/hldr created\ngroup/work created\n"], [status, out]
      assert_equal "error: #{file}:2: \"kind\" must be Project or Group, not \"Pod\"\n", err
    end
  end

  def test_error_prefixes_are_painted_on_every_line
    with_runtime do |runtime, home|
      a = write(home, 'a.yaml', "kind: Project\n")
      b = write(home, 'b.yaml', "kind: Group\n")
      _, out, err = run_apply('-f', a, '-f', b, '--color=always', runtime:)

      assert_equal '', out
      assert_equal "\e[31merror:\e[0m #{a}: \"metadata.name\" is required\n" \
                   "\e[31merror:\e[0m #{b}: \"metadata.name\" is required\n", err
    end
  end

  def test_empty_input_and_empty_directories_are_errors
    with_runtime do |runtime, home|
      empty = write(home, 'empty.yaml', "---\n")
      dir = File.join(home, 'nothing')
      FileUtils.mkdir_p(dir)

      assert_equal [1, '', "error: no objects passed to apply\n"], run_apply('-f', empty, runtime:)
      assert_equal [1, '', "error: #{dir}: no .yaml or .yml files\n"], run_apply('-f', dir, runtime:)
    end
  end

  def test_dry_run_reports_every_outcome_and_writes_nothing
    with_runtime do |runtime, home|
      register(runtime, 'hldr', description: 'Old')
      file = write(home, 'all.yaml', "#{WORK}---\n#{API}---\n#{HLDR}  description: New\n")
      hldr = write(home, 'hldr.yaml', "#{HLDR}  description: Old\n")

      assert_equal [0, "group/work created (dry run)\nproject/api created (dry run)\n" \
                       "project/hldr configured (dry run)\n", ''], run_apply('-f', file, '--dry-run', runtime:)
      assert_equal [0, "project/hldr \e[35munchanged\e[0m \e[36m(dry run)\e[0m\n", ''],
                   run_apply('-f', hldr, '--dry-run', '--color', runtime:)
      assert_equal 'Old', runtime.store.find(PROJECTS, 'hldr', group: nil).description
      assert_equal %w[default], runtime.store.names(GROUPS)
      assert_equal %w[hldr], runtime.store.names(PROJECTS)
    end
  end

  def test_dry_run_still_requires_the_group_of_a_new_project
    with_runtime do |runtime, home|
      file = write(home, 'api.yaml', API)

      assert_equal [1, '', "error: #{file}: groups \"work\" not found\n"],
                   run_apply('-f', file, '--dry-run', runtime:)
      register_group(runtime, 'work')

      assert_equal [0, "project/api created (dry run)\n", ''], run_apply('-f', file, '--dry-run', runtime:)
      assert_empty runtime.store.names(PROJECTS)
    end
  end

  def test_help_flags_and_completion
    with_runtime do |runtime|
      status, out, err = run_apply('--help', runtime:)
      option = Slipway::Commands::Apply::FILENAME

      assert_equal [0, ''], [status, err]
      assert_includes out, "Usage:\n  slipway apply -f FILE [flags]\n"
      assert_includes out, '  -f, --filename FILE'
      assert_equal [2, '', "error: required flag(s) \"--filename\" not set\nSee 'slipway apply --help' for usage.\n"],
                   run_apply(runtime:)
      assert_equal Slipway::CLI::Completer::FILES, option.candidates([])
      assert_predicate option, :repeatable
    end
  end

  private

  def run_apply(*argv, runtime:, **)
    run_commands('apply', *argv, runtime:, commands: [Slipway::Commands::Apply], **)
  end

  def write(dir, name, text)
    FileUtils.mkdir_p(dir)
    path = File.join(dir, name)
    File.write(path, text)
    path
  end

  def with_stdin(text)
    original = $stdin
    $stdin = StringIO.new(text)
    yield
  ensure
    $stdin = original
  end
end
