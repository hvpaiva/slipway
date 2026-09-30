# frozen_string_literal: true

require 'test_helper'
require 'rbconfig'
require 'shellwords'
require 'tmpdir'
require 'slipway/editor'

class EditorTest < Minitest::Test
  def test_command_precedence
    env = { 'SLIPWAY_EDITOR' => 'nvim', 'VISUAL' => 'code --wait', 'EDITOR' => 'nano' }

    assert_equal %w[nvim], editor(env, preferred: 'emacs').command
    assert_equal %w[emacs], editor(env.except('SLIPWAY_EDITOR'), preferred: 'emacs').command
    assert_equal %w[code --wait], editor(env.except('SLIPWAY_EDITOR')).command
    assert_equal %w[nano], editor(env.slice('EDITOR')).command
    assert_equal %w[vi], editor({}).command
  end

  def test_blank_values_are_skipped
    env = { 'SLIPWAY_EDITOR' => '', 'VISUAL' => '  ', 'EDITOR' => 'nano' }

    assert_equal %w[nano], editor(env, preferred: '').command
  end

  def test_command_splits_like_a_shell_without_running_one
    env = { 'SLIPWAY_EDITOR' => %q("/Applications/Sublime Text.app/bin/subl" -w -c 'set ft=yaml') }

    assert_equal ['/Applications/Sublime Text.app/bin/subl', '-w', '-c', 'set ft=yaml'], editor(env).command
  end

  def test_unbalanced_quotes_are_reported
    error = assert_raises(Slipway::Editor::Failed) { editor({ 'SLIPWAY_EDITOR' => 'vim "-c' }).command }

    assert_operator error.message, :start_with?, 'editor "vim \"-c" is not a valid command line: Unmatched quote at 4'
  end

  def test_edit_returns_what_the_editor_saved
    with_fake_editor("printf 'spec:\\n  path: ~/x\\n' >> \"$1\"\n") do |script|
      result = editor({ 'EDITOR' => script }).edit("kind: Project\n")

      assert_equal "kind: Project\nspec:\n  path: ~/x\n", result
    end
  end

  def test_edit_uses_the_requested_file_name_and_removes_the_directory
    with_fake_editor("printf '%s' \"$1\" > \"$FAKE_EDITOR_LOG\"\n") do |script, log|
      editor({ 'EDITOR' => script }).edit('text', filename: 'hldr.yaml')
      opened = File.read(log)

      assert_equal 'hldr.yaml', File.basename(opened)
      assert_match(/slipway-edit-/, File.dirname(opened))
      refute_path_exists File.dirname(opened)
    end
  end

  def test_an_editor_that_removes_the_file_cancels_the_edit
    with_fake_editor("rm \"$1\"\n") do |script|
      error = assert_raises(Slipway::Editor::Failed) { editor({ 'EDITOR' => script }).edit('text', filename: 'p1.yaml') }

      assert_equal 'editor removed p1.yaml; edit cancelled', error.message
    end
  end

  def test_edit_runs_a_quoted_ruby_one_liner_through_shellwords
    program = "#{Shellwords.escape(RbConfig.ruby)} -e 'File.write(ARGV[0], File.read(ARGV[0]).upcase)'"
    result = editor({ 'SLIPWAY_EDITOR' => program }).edit("name: hldr\n")

    assert_equal "NAME: HLDR\n", result
  end

  def test_non_zero_exit_fails_with_the_status
    with_fake_editor("exit 1\n") do |script|
      error = assert_raises(Slipway::Editor::Failed) { editor({ 'EDITOR' => "#{script} --flag" }).edit('text') }

      assert_equal "editor #{script.inspect} exited with status 1", error.message
    end
  end

  def test_signal_death_is_reported
    with_fake_editor("kill -KILL $$\n") do |script|
      error = assert_raises(Slipway::Editor::Failed) { editor({ 'EDITOR' => script }).edit('text') }

      assert_equal "editor #{script.inspect} was killed by signal 9", error.message
    end
  end

  # A private TMPDIR, because another slipway run sharing /tmp can create and remove its own
  # slipway-edit-* directories while this test compares snapshots.
  def test_missing_editor_is_reported_and_leaves_nothing_behind
    Dir.mktmpdir('slipway-editor-test-') do |tmp|
      error = with_env('TMPDIR' => tmp) do
        assert_raises(Slipway::Editor::Failed) { editor({ 'EDITOR' => 'slipway-no-such-editor' }).edit('text') }
      end

      assert_equal 'editor "slipway-no-such-editor" not found', error.message
      assert_empty Dir.children(tmp)
    end
  end

  def test_failed_is_a_slipway_error
    assert_operator Slipway::Editor::Failed, :<, Slipway::Error
    assert_equal 1, Slipway::Editor::Failed.new('x').exit_status
  end

  private

  def editor(env, preferred: nil) = Slipway::Editor.new(env:, preferred:)

  def with_fake_editor(body)
    Dir.mktmpdir('slipway-fake-editor-') do |dir|
      script = File.join(dir, 'fake-editor')
      log = File.join(dir, 'log')
      File.write(script, "#!/bin/sh\n#{body}")
      File.chmod(0o755, script)
      with_env('FAKE_EDITOR_LOG' => log) { yield script, log }
    end
  end

  # The fake editor inherits the real process environment, so the log path travels through ENV.
  def with_env(pairs)
    previous = pairs.to_h { |key, _| [key, ENV.fetch(key, nil)] }
    pairs.each { |key, value| ENV[key] = value }
    yield
  ensure
    previous.each { |key, value| ENV[key] = value }
  end
end
