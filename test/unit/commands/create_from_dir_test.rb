# frozen_string_literal: true

require 'test_helper'
require 'tmpdir'

class CreateFromDirTest < Minitest::Test
  include FromDirHelper

  def test_every_clone_is_registered_with_its_path_and_its_origin
    with_runtime do |runtime, home|
      clone_at(runtime, File.join(home, 'dev', 'hldr'), remote: 'git@github.com:hvpaiva/hldr.git')
      clone_at(runtime, File.join(home, 'dev', 'My.Notes_v2'))

      assert_equal [0, "project/my-notes-v2 created\nproject/hldr created\n", ''],
                   run_create('project', '--from-dir', '~/dev', runtime:)
      assert_equal({ 'hldr' => ['~/dev/hldr', 'git@github.com:hvpaiva/hldr.git'],
                     'my-notes-v2' => ['~/dev/My.Notes_v2', nil] }, stored(runtime))
    end
  end

  def test_credentials_are_dropped_from_the_origin_before_it_is_recorded
    with_runtime do |runtime, home|
      clone_at(runtime, File.join(home, 'dev', 'api'), remote: 'https://ci:s3cret@example.com/o/api.git')
      clone_at(runtime, File.join(home, 'dev', 'ops'), remote: 'ssh://deploy:s3cret@example.com/o/ops.git')

      assert_equal [0, "project/api created\nproject/ops created\n", ''],
                   run_create('project', '--from-dir', '~/dev', runtime:)
      assert_equal({ 'api' => ['~/dev/api', 'https://example.com/o/api.git'],
                     'ops' => ['~/dev/ops', 'ssh://deploy@example.com/o/ops.git'] }, stored(runtime))
    end
  end

  def test_an_origin_the_manifest_would_refuse_is_left_out_with_a_warning
    with_runtime do |runtime, home|
      clone_at(runtime, File.join(home, 'dev', 'scp'), remote: 'deploy:s3cret@example.com:o/scp.git')
      clone_at(runtime, File.join(home, 'dev', 'local'), remote: "/srv/git/local\e[2J.git")
      status, out, err = run_create('project', '--from-dir', '~/dev', runtime:)

      assert_equal [0, "project/local created\nproject/scp created\n"], [status, out]
      assert_equal 'warning: ~/dev/local: spec.remote left out: "/srv/git/local\e[2J.git" is not a valid remote ' \
                   "URL: #{Slipway::Git::Url::RULE}\n" \
                   'warning: ~/dev/scp: spec.remote left out: origin must not embed credentials; use a credential ' \
                   "helper\n", err
      refute_includes err, 's3cret'
      assert_equal({ 'local' => ['~/dev/local', nil], 'scp' => ['~/dev/scp', nil] }, stored(runtime))
    end
  end

  def test_a_directory_name_reaches_the_warning_line_neutralized
    with_runtime do |runtime, home|
      clone_at(runtime, File.join(home, 'dev', "tty\e]0;x\a"), remote: 'deploy:s3cret@example.com:o/tty.git')
      status, out, err = run_create('project', '--from-dir', '~/dev', runtime:)

      assert_equal [0, "project/tty-0-x created\n"], [status, out]
      assert_equal 'warning: ~/dev/tty^[]0;x^G: spec.remote left out: origin must not embed credentials; use a ' \
                   "credential helper\n", err
      refute_includes err, "\e"
      assert_equal({ 'tty-0-x' => ["~/dev/tty\e]0;x\a", nil] }, stored(runtime))
    end
  end

  def test_a_path_already_registered_is_unchanged_whatever_its_name
    with_runtime do |runtime, home|
      clone_at(runtime, File.join(home, 'dev', 'hldr'))
      clone_at(runtime, File.join(home, 'dev', 'site'))
      runtime.store.create(Slipway::Project.new(name: 'blog', path: File.join(home, 'dev', 'site')))

      assert_equal [0, "project/hldr created\nproject/blog unchanged\n", ''],
                   run_create('project', '--from-dir', '~/dev', runtime:)
      assert_equal [0, "project/hldr \e[35munchanged\e[0m\nproject/blog \e[35munchanged\e[0m\n", ''],
                   run_create('project', '--from-dir', "#{home}/dev/", '--color', runtime:)
      assert_equal %w[blog hldr], runtime.store.names(PROJECTS)
    end
  end

  def test_a_clone_reached_through_a_symbolic_link_is_the_one_registered
    with_runtime do |runtime, home|
      real = clone_at(runtime, File.join(home, 'data', 'dev', 'hldr'))
      File.symlink(File.join(home, 'data', 'dev'), File.join(home, 'dev'))
      runtime.store.create(Slipway::Project.new(name: 'other', path: File.realpath(real)))

      assert_equal [0, "project/other unchanged\n", ''], run_create('project', '--from-dir', '~/dev', runtime:)
      assert_equal %w[other], runtime.store.names(PROJECTS)
    end
  end

  def test_a_stored_path_slipway_does_not_expand_keeps_its_name_taken
    with_runtime do |runtime, home|
      clone_at(runtime, File.join(home, 'dev', 'hldr'))
      clone_at(runtime, File.join(home, 'dev', 'x'))
      runtime.store.create(Slipway::Project.new(name: 'x', path: '~nosuchuser/x'))

      assert_equal [1, "project/hldr created\n", "error: ~/dev/x: project \"x\" already exists at ~nosuchuser/x\n"],
                   run_create('project', '--from-dir', '~/dev', runtime:)
    end
  end

  def test_a_name_taken_by_another_path_is_an_error_after_the_successes
    with_runtime do |runtime, home|
      %w[Foo a-b a_b zed].each { clone_at(runtime, File.join(home, 'dev', it)) }
      runtime.store.create(Slipway::Project.new(name: 'zed', path: '~/elsewhere/zed'))
      status, out, err = run_create('project', '--from-dir', '~/dev', runtime:)

      assert_equal [1, "project/foo created\nproject/a-b created\n"], [status, out]
      assert_equal "error: ~/dev/a_b: project \"a-b\" already exists at ~/dev/a-b\n" \
                   "error: ~/dev/zed: project \"zed\" already exists at ~/elsewhere/zed\n", err
    end
  end

  def test_a_dry_run_writes_nothing_and_still_sees_the_names_it_would_take
    with_runtime do |runtime, home|
      %w[a-b a_b].each { clone_at(runtime, File.join(home, 'dev', it)) }

      result = run_create('project', '--from-dir', '~/dev', '--dry-run=client', runtime:)

      assert_equal [1, "project/a-b created (dry run)\n",
                    "error: ~/dev/a_b: project \"a-b\" already exists at ~/dev/a-b\n"], result
      assert_empty runtime.store.list(PROJECTS)
      refute runtime.store.exist?(Slipway::Resources.resolve('groups'), 'default')
    end
  end

  def test_labels_and_the_group_apply_to_every_project_created
    with_runtime do |runtime, home|
      register_group(runtime, 'personal')
      %w[one two].each { clone_at(runtime, File.join(home, 'dev', it)) }

      assert_equal [0, "project/one created\nproject/two created\n", ''],
                   run_create('project', '--from-dir', '~/dev', '-n', 'personal', '--label', 'lang=rust', runtime:)
      assert_equal([{ 'lang' => 'rust' }] * 2, runtime.store.list(PROJECTS, group: 'personal').map(&:labels))
      assert_equal [1, '', "error: groups \"work\" not found\n"],
                   run_create('project', '--from-dir', '~/dev', '-n', 'work', '--dry-run=client', runtime:)
    end
  end

  def test_a_directory_that_is_a_clone_registers_itself
    with_runtime do |runtime, home|
      clone_at(runtime, home)
      clone_at(runtime, File.join(home, 'dev', 'inside'))
      name = File.basename(home).downcase.gsub(/[^a-z0-9-]+/, '-')

      assert_equal [0, "project/#{name} created\n", ''], run_create('project', '--from-dir', '~', runtime:)
      assert_equal({ name => ['~', nil] }, stored(runtime))
    end
  end

  def test_a_clone_outside_home_keeps_its_absolute_path
    with_runtime do |runtime|
      Dir.mktmpdir('slipway-outside-') do |outside|
        clone_at(runtime, File.join(outside, 'tool'))

        assert_equal [0, "project/tool created\n", ''], run_create('project', '--from-dir', outside, runtime:)
        assert_equal({ 'tool' => [File.join(outside, 'tool'), nil] }, stored(runtime))
      end
    end
  end

  def test_a_relative_directory_is_resolved_against_the_current_one
    with_runtime do |runtime, home|
      clone_at(runtime, File.join(home, 'dev', 'here'))

      Dir.chdir(File.join(home, 'dev', 'here')) do
        assert_equal [0, "project/here created\n", ''], run_create('project', '--from-dir', '.', runtime:)
      end
      assert_equal File.realpath(File.join(home, 'dev', 'here')),
                   File.realpath(Slipway::Paths.expand(stored(runtime).dig('here', 0), home:))
    end
  end
end
