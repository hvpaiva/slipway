# frozen_string_literal: true

require 'json'
require 'shellwords'
require 'test_helper'

class CreateFromDirUsageTest < Minitest::Test
  include FromDirHelper

  def test_either_name_or_from_dir_names_the_project
    with_runtime do |runtime|
      either = [2, '', "error: give either NAME or --from-dir, not both\n#{HINT}"]

      assert_equal either, run_create('project', 'hldr', '--from-dir', '~/dev', runtime:)
      assert_equal either, run_create('project/hldr', '--from-dir', '~/dev', runtime:)
      assert_equal [2, '', "error: missing required argument \"NAME\"\n#{HINT}"], run_create('project', runtime:)
      assert_equal [2, '', "error: flag --from-dir applies to projects only\n#{HINT}"],
                   run_create('group', '--from-dir', '~/dev', runtime:)
    end
  end

  def test_flags_that_describe_one_project_are_refused_with_from_dir
    with_runtime do |runtime|
      { '--path' => 'path', '--description' => 'description', '--remote' => 'remote',
        '--branch' => 'branch' }.each do |flag, name|
        assert_equal [2, '', "error: flag --#{name} cannot be used with --from-dir\n#{HINT}"],
                     run_create('project', '--from-dir', '~/dev', flag, 'x', runtime:)
      end
      assert_equal [2, '', "error: flag --from-dir must not be empty\n#{HINT}"],
                   run_create('project', '--from-dir', ' ', runtime:)
    end
  end

  def test_depth_is_refused_without_from_dir
    with_runtime do |runtime|
      refused = [2, '', "error: flag --depth requires --from-dir\n#{HINT}"]

      assert_equal refused, run_create('project', 'b', '--path', '~/b', '--depth', '2', runtime:)
      assert_equal refused, run_create('group', 'g', '--depth', '2', runtime:)
      assert_empty runtime.store.list(PROJECTS)
    end
  end

  def test_depth_is_an_integer_from_one_to_eight
    with_runtime do |runtime, home|
      clone_at(runtime, File.join(home, 'dev', 'a', 'b', 'c', 'deep'))

      %w[0 9 two 1.5].each do |depth|
        assert_equal [2, '', "error: invalid argument #{depth.inspect} for --depth: must be an integer from 1 to 8\n" \
                             "#{HINT}"], run_create('project', '--from-dir', '~/dev', '--depth', depth, runtime:)
      end
      assert_equal [0, "project/deep created (dry run)\n", ''],
                   run_create('project', '--from-dir', '~/dev', '--depth=4', '--dry-run', runtime:)
    end
  end

  def test_a_directory_without_clones_or_that_does_not_exist_is_an_error
    with_runtime do |runtime, home|
      FileUtils.mkdir_p(File.join(home, 'dev', 'a', 'deep', '.git'))

      assert_equal [1, '', "error: no git repositories found under ~/dev to depth 1\n"],
                   run_create('project', '--from-dir', '~/dev', runtime:)
      assert_equal [1, '', "error: #{home}/nope: no such directory\n"],
                   run_create('project', '--from-dir', '~/nope', runtime:)
    end
  end

  def test_output_name_and_yaml_list_every_project_found
    with_runtime do |runtime, home|
      clone_at(runtime, File.join(home, 'dev', 'hldr'), remote: 'git@github.com:hvpaiva/hldr.git')
      clone_at(runtime, File.join(home, 'dev', 'notes'))
      runtime.store.create(Slipway::Project.new(name: 'notes', path: '~/dev/notes', labels: { 'kind' => 'docs' }))
      status, out, err = run_create('project', '--from-dir', '~/dev', '--dry-run', '-o', 'yaml', runtime:)

      assert_equal [0, "project/hldr\nproject/notes\n", ''],
                   run_create('project', '--from-dir', '~/dev', '--dry-run', '-o', 'name', runtime:)
      assert_equal [0, ''], [status, err]
      assert_equal([['hldr', 'git@github.com:hvpaiva/hldr.git', {}], ['notes', nil, { 'kind' => 'docs' }]],
                   summary(Slipway::Manifest.load_objects(out, source: 'out')))
      assert_equal %w[notes], runtime.store.names(PROJECTS)
    end
  end

  def test_output_json_is_a_list_even_for_one_project
    with_runtime do |runtime, home|
      clone_at(runtime, File.join(home, 'dev', 'solo'))
      status, out, err = run_create('project', '--from-dir', '~/dev', '-o', 'json', runtime:)

      list = JSON.parse(out)

      assert_equal [0, ''], [status, err]
      assert_equal ['List', ['solo']], [list['kind'], list['items'].map { it['metadata']['name'] }]
    end
  end

  def test_git_failures_and_unreadable_manifests_are_reported_per_path
    with_runtime do |runtime, home|
      clone_at(runtime, File.join(home, 'dev', 'good'))
      broken = clone_at(runtime, File.join(home, 'dev', 'broken'))
      runtime.git.fail(broken, Slipway::Git::NotARepository)
      clone_at(runtime, File.join(home, 'dev', 'odd'))
      bad = File.join(runtime.store.root, 'projects', 'default', 'odd.yaml')
      FileUtils.mkdir_p(File.dirname(bad))
      File.write(bad, "kind: Pod\n")
      status, out, err = run_create('project', '--from-dir', '~/dev', runtime:)

      assert_equal [1, "project/good created\n"], [status, out]
      assert_equal "warning: #{bad}: \"kind\" must be Project or Group, not \"Pod\"\n" \
                   "error: ~/dev/broken: not a git repository\n" \
                   "error: ~/dev/odd: project \"odd\" already exists\n", err
    end
  end

  def test_a_repository_git_distrusts_is_skipped_with_the_command_that_trusts_it
    with_runtime do |runtime, home|
      clone_at(runtime, File.join(home, 'dev', 'mine'))
      runtime.git.fail(clone_at(runtime, File.join(home, 'dev', 'theirs')), Slipway::Git::UnsafeRepository)

      assert_equal [1, "project/mine created\n",
                    "error: ~/dev/theirs: repository has dubious ownership. Run 'git config --global --add " \
                    "safe.directory #{Shellwords.escape(File.join(home, 'dev', 'theirs'))}' to trust it.\n"],
                   run_create('project', '--from-dir', '~/dev', runtime:)
      assert_equal %w[mine], runtime.store.names(PROJECTS)
    end
  end

  def test_an_unreadable_directory_is_reported_and_the_others_are_registered
    skip 'root can read anything' if Process.uid.zero?

    with_runtime do |runtime, home|
      clone_at(runtime, File.join(home, 'dev', 'open', 'one'))
      locked = File.join(home, 'dev', 'locked')
      FileUtils.mkdir_p(locked)
      File.chmod(0o000, locked)

      assert_equal [1, "project/one created\n", "error: ~/dev/locked: Permission denied\n"],
                   run_create('project', '--from-dir', '~/dev', '--depth', '2', runtime:)
    ensure
      File.chmod(0o700, locked) if locked
    end
  end

  def test_a_path_that_is_not_utf8_is_reported
    with_runtime do |runtime, home|
      odd = File.join(home, 'dev', (+"caf\xE9").force_encoding(Encoding::UTF_8))
      begin
        FileUtils.mkdir_p(File.join(odd, '.git'))
      rescue SystemCallError
        skip 'this file system refuses names that are not UTF-8'
      end

      assert_equal [1, '', "error: ~/dev/caf�: path is not valid UTF-8\n"],
                   run_create('project', '--from-dir', '~/dev', runtime:)
    end
  end

  private

  def summary(manifests) = manifests.map { [it['metadata']['name'], it['spec']['remote'], it['metadata']['labels']] }
end
