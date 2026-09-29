# frozen_string_literal: true

require 'test_helper'

class EditTest < Minitest::Test
  include CommandsHelper

  HEADER = Slipway::Commands::Edit::HEADER
  DUMP = <<~YAML
    kind: Project
    metadata:
      name: hldr
      group: default
      labels:
        lang: rust
      creationTimestamp: '2026-09-29T09:00:00Z'
    spec:
      path: "~/dev/hldr"
  YAML
  # Every fake editor logs one line per run and keeps a copy of each buffer it was handed.
  PRELUDE = <<~SH
    echo run >> "$LOG"
    n=$(wc -l < "$LOG" | tr -d ' ')
    cp "$1" "$LOG.$n"
  SH
  BREAK_ONCE = %(if [ "$n" = 1 ]; then printf 'extra: 1\\n' >> "$1"; fi\n)
  ABORTED = [1, '', "error: Edit cancelled, no valid changes were saved.\n"].freeze
  REOPENED_WITH_SYNTAX_ERROR = /\A#{Regexp.escape(HEADER)}# edited manifest: .+ at line \d+, column \d+\n#\n/

  def test_the_editor_receives_the_header_and_the_manifest_under_the_resource_name
    with_editor("printf '%s' \"$1\" > \"$LOG.name\"\n") do |runtime, log|
      register(runtime, 'hldr', labels: { 'lang' => 'rust' })

      run_edit('project', 'hldr', runtime:)

      assert_equal "#{HEADER}#{DUMP}", File.read("#{log}.1")
      assert_equal 'hldr.yaml', File.basename(File.read("#{log}.name"))
    end
  end

  def test_an_untouched_file_cancels_with_no_changes_made
    with_editor('') do |runtime, log|
      register(runtime, 'hldr', labels: { 'lang' => 'rust' })

      assert_equal [0, '', "Edit cancelled, no changes made.\n"], run_edit('project', 'hldr', runtime:)
      assert_equal 1, runs(log)
    end
  end

  def test_an_empty_file_aborts_with_exit_one
    with_editor(%(: > "$1"\n)) do |runtime, log|
      register(runtime, 'hldr')

      assert_equal ABORTED, run_edit('project', 'hldr', runtime:)
      assert_equal 1, runs(log)
      assert_equal 'hldr', runtime.store.find(kind('project'), 'hldr', group: 'default').name
    end
  end

  def test_a_file_holding_only_comments_counts_as_empty
    with_editor(%(printf '# nothing\\n\\n' > "$1"\n)) do |runtime|
      register(runtime, 'hldr')

      assert_equal ABORTED, run_edit('project', 'hldr', runtime:)
    end
  end

  def test_an_added_label_is_saved_and_reported_as_edited
    with_editor(%(sed -i 's/^    lang: rust$/&\\n    team: core/' "$1"\n)) do |runtime|
      register(runtime, 'hldr', labels: { 'lang' => 'rust' })

      assert_equal [0, "project/hldr edited\n", ''], run_edit('project', 'hldr', runtime:)
      saved = runtime.store.find(kind('project'), 'hldr', group: 'default')

      assert_equal({ 'lang' => 'rust', 'team' => 'core' }, saved.labels)
      assert_equal CREATED, saved.created_at
    end
  end

  def test_the_verb_is_painted_like_apply_configured
    with_editor(%(sed -i 's/^    lang: rust$/&\\n    team: core/' "$1"\n)) do |runtime|
      register(runtime, 'hldr', labels: { 'lang' => 'rust' })

      _, out, = run_edit('project', 'hldr', '--color', runtime:)

      assert_equal "project/hldr \e[33medited\e[0m\n", out
    end
  end

  def test_an_omitted_creation_timestamp_keeps_the_original
    body = %(sed -i '/^  creationTimestamp: /d; s|~/dev/hldr|~/dev/moved|' "$1"\n)
    with_editor(body) do |runtime|
      register(runtime, 'hldr')

      assert_equal [0, "project/hldr edited\n", ''], run_edit('projects', 'hldr', runtime:)
      saved = runtime.store.find(kind('project'), 'hldr', group: 'default')

      assert_equal ['~/dev/moved', CREATED], [saved.path, saved.created_at]
    end
  end

  def test_changed_text_that_describes_the_same_object_is_skipped
    with_editor(%(printf '\\n\\n' >> "$1"\n)) do |runtime|
      register(runtime, 'hldr')
      before = File.read(project_file(runtime, 'hldr'))

      assert_equal [0, "project/hldr skipped\n", ''], run_edit('project', 'hldr', runtime:)
      assert_equal before, File.read(project_file(runtime, 'hldr'))
    end
  end

  def test_a_group_can_be_edited_in_place
    with_editor(%(sed -i 's/^spec: {}$/spec:\\n  description: Day job/' "$1"\n)) do |runtime|
      register_group(runtime, 'work')

      assert_equal [0, "group/work edited\n", ''], run_edit('group', 'work', runtime:)
      assert_equal 'Day job', runtime.store.find(kind('groups'), 'work', group: nil).description
    end
  end

  def test_an_invalid_file_is_reopened_with_the_failure_as_a_comment_until_it_is_fixed
    fix = %(sed -i '/^extra: 1$/d; s|~/dev/hldr|~/dev/moved|' "$1"\n)
    with_editor(%(if [ "$n" = 1 ]; then printf 'extra: 1\\n' >> "$1"; else #{fix.chomp}; fi\n)) do |runtime, log|
      register(runtime, 'hldr', labels: { 'lang' => 'rust' })

      assert_equal [0, "project/hldr edited\n", ''], run_edit('project', 'hldr', runtime:)
      assert_equal 2, runs(log)
      assert_equal "#{HEADER}# edited manifest: unknown field \"extra\"\n#\n#{DUMP}extra: 1\n", File.read("#{log}.2")
      assert_equal '~/dev/moved', runtime.store.find(kind('project'), 'hldr', group: 'default').path
    end
  end

  def test_saving_the_reopened_file_unchanged_aborts
    with_editor(BREAK_ONCE) do |runtime, log|
      register(runtime, 'hldr')

      assert_equal ABORTED, run_edit('project', 'hldr', runtime:)
      assert_equal 2, runs(log)
      assert_equal '~/dev/hldr', runtime.store.find(kind('project'), 'hldr', group: 'default').path
    end
  end

  def test_a_syntax_error_names_the_line_and_column
    with_editor(%(if [ "$n" = 1 ]; then printf 'path: [\\n' >> "$1"; fi\n)) do |runtime, log|
      register(runtime, 'hldr')

      assert_equal 1, run_edit('project', 'hldr', runtime:).first
      assert_match REOPENED_WITH_SYNTAX_ERROR, File.read("#{log}.2")
    end
  end

  def test_the_name_cannot_be_changed
    assert_immutable(%(if [ "$n" = 1 ]; then sed -i 's/^  name: hldr$/  name: other/' "$1"; fi\n))
  end

  def test_the_group_cannot_be_changed
    assert_immutable(%(if [ "$n" = 1 ]; then sed -i 's/^  group: default$/  group: work/' "$1"; fi\n))
  end

  def test_the_kind_cannot_be_changed
    assert_immutable(%(if [ "$n" = 1 ]; then printf 'kind: Group\\nmetadata:\\n  name: hldr\\n' > "$1"; fi\n))
  end

  def test_the_configured_editor_is_used_when_no_variable_names_one
    with_sandbox do |env|
      script = fake_editor(env, %(sed -i 's/^spec: {}$/spec:\\n  description: Day job/' "$1"\n))
      write_config(env, "editor: #{script}\n")
      runtime = sandbox_runtime(env)
      register_group(runtime, 'work')

      assert_equal [0, "group/work edited\n", ''], run_edit('group', 'work', runtime:)
    end
  end

  def test_an_editor_that_fails_is_reported
    with_editor("exit 3\n") do |runtime|
      register(runtime, 'hldr')

      status, out, err = run_edit('project', 'hldr', runtime:)

      assert_equal [1, ''], [status, out]
      assert_equal "error: editor #{runtime.env['EDITOR'].inspect} exited with status 3\n", err
    end
  end

  def test_unknown_resources_and_types_are_reported_before_the_editor_runs
    with_editor('') do |runtime, log|
      register(runtime, 'hldr')

      assert_equal [1, '', "error: projects \"nope\" not found\n"], run_edit('project', 'nope', runtime:)
      assert_equal [1, '', "error: projects \"hldr\" not found\n"], run_edit('project', 'hldr', '-n', 'work', runtime:)
      assert_equal [1, '', "error: unknown resource type \"pod\"\n"], run_edit('pod', 'hldr', runtime:)
      refute_path_exists log
    end
  end

  def test_arity_is_checked
    with_editor('') do |runtime|
      assert_equal [2, '', "error: missing required argument \"NAME\"\nSee 'slipway edit --help' for usage.\n"],
                   run_edit('project', runtime:)
      assert_equal [2, '', "error: unexpected argument \"extra\"\nSee 'slipway edit --help' for usage.\n"],
                   run_edit('project', 'hldr', 'extra', runtime:)
    end
  end

  def test_help_follows_the_registry
    with_editor('') do |runtime|
      status, out, err = run_edit('--help', runtime:)

      assert_equal [0, ''], [status, err]
      assert_includes out, "Edit a resource from the default editor.\n\nThe edit command"
      assert_includes out, "Examples:\n  # Edit the project named 'hldr'\n  slipway edit project hldr\n"
      assert_includes out, "Usage:\n  slipway edit TYPE NAME\n"
    end
  end

  private

  def kind(word) = Slipway::Resources.resolve(word)

  def runs(log) = File.readlines(log).size

  def project_file(runtime, name) = File.join(runtime.store.root, 'projects', 'default', "#{name}.yaml")

  def run_edit(*argv, runtime:)
    run_commands('edit', *argv, runtime:, commands: [Slipway::Commands::Edit])
  end

  # An identity change is reopened with the immutability message; saving it as is aborts.
  def assert_immutable(body)
    with_editor(body) do |runtime, log|
      register(runtime, 'hldr')

      assert_equal ABORTED, run_edit('project', 'hldr', runtime:)
      assert_equal 2, runs(log)
      assert_includes File.read("#{log}.2"),
                      "#\n# edited manifest: kind, metadata.name and metadata.group cannot be changed\n#\n"
    end
  end

  # Yields a runtime whose EDITOR is a shell script running PRELUDE then +body+, and its log path.
  def with_editor(body)
    with_sandbox do |env|
      script = fake_editor(env, body)
      yield sandbox_runtime(env.merge('EDITOR' => script)), File.join(env['HOME'], 'editor.log')
    end
  end

  def fake_editor(env, body)
    script = File.join(env['HOME'], 'fake-editor')
    File.write(script, "#!/bin/sh\nLOG=#{File.join(env['HOME'], 'editor.log')}\n#{PRELUDE}#{body}")
    File.chmod(0o755, script)
    script
  end

  def write_config(env, text)
    path = File.join(env['XDG_CONFIG_HOME'], 'slipway', 'config.yaml')
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, text)
  end
end
