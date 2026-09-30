# frozen_string_literal: true

require 'test_helper'

class EditIntegrationTest < Minitest::Test
  include IntegrationHelper
  include EditorScripts

  BUFFER = <<~TEXT.freeze
    # Please edit the object below. Lines beginning with a '#' will be ignored,
    # and an empty file will abort the edit. If an error occurs while saving this
    # file will be reopened with the relevant failures.
    #
    kind: Project
    metadata:
      name: clean
      group: default
      labels:
        lang: rust
      creationTimestamp: '#{CREATED}'
    spec:
      path: "~/dev/clean"
  TEXT

  # Round one breaks the manifest; round two, seeing the reopened file, fixes it.
  TWO_STEP = <<~SH.freeze
    echo "---- round" >> "<log>"
    cat "$1" >> "<log>"
    if grep -q 'was not valid:' "$1"; then
      #{EditorScripts.rewrite('$_.sub!(/^  path: .*/, %q(  path: "~/dev/moved"))')}
    else
      printf 'spec:\\n  path: 1\\n' >> "$1"
    fi
  SH

  # The first save sets an invalid branch; the second, seeing the reopened file, sets a valid one.
  BRANCH_TWO_STEP = <<~SH.freeze
    echo "---- round" >> "<log>"
    cat "$1" >> "<log>"
    if grep -q 'was not valid:' "$1"; then
      #{EditorScripts.rewrite('$_.sub!(/^  branch: .*/, %q(  branch: release/1.x))')}
    else
      #{EditorScripts.rewrite('$_.sub!(/^  branch: .*/, %q(  branch: --track))')}
    fi
  SH

  def seed_clean(env)
    seed(env, manifest('Project', 'clean', path: repo(env, 'clean'), labels: { 'lang' => 'rust' }))
  end

  def label_editor(env)
    editor_script(env, 'add-label.sh', rewrite('$_ << %q(    edited: "yes") << "\n" if $_ == "    lang: rust\n"'))
  end

  def test_a_changed_manifest_is_saved
    with_home do |env|
      seed_clean(env)
      status, out, err = slipway('edit', 'project', 'clean', env: env.merge('EDITOR' => label_editor(env)))

      assert_equal [0, "project/clean edited\n", ''], [status, out, err]
      assert_equal "edited=yes\nlang=rust\n", slipway!('label', 'project', 'clean', '--list', env:)
    end
  end

  def test_the_editor_sees_the_header_comment_above_the_manifest
    with_home do |env|
      seed_clean(env)
      seen = File.join(env['HOME'], 'seen.yaml')
      editor = editor_script(env, 'record.sh', %(cp "$1" "#{seen}"))
      slipway('edit', 'project', 'clean', env: env.merge('EDITOR' => editor))

      assert_equal BUFFER, File.read(seen)
    end
  end

  def test_an_unchanged_file_cancels_quietly
    with_home do |env|
      seed_clean(env)
      status, out, err = slipway('edit', 'project', 'clean',
                                 env: env.merge('EDITOR' => editor_script(env, 'noop.sh', ':')))

      assert_equal [0, '', "Edit cancelled, no changes made.\n"], [status, out, err]
    end
  end

  def test_an_empty_file_aborts
    with_home do |env|
      seed_clean(env)
      editor = editor_script(env, 'empty.sh', %(: > "$1"))
      status, out, err = slipway('edit', 'project', 'clean', env: env.merge('EDITOR' => editor))

      assert_equal [1, '', "error: Edit cancelled, saved file was empty.\n"], [status, out, err]
      assert_equal "lang=rust\n", slipway!('label', 'project', 'clean', '--list', env:)
    end
  end

  def test_an_invalid_manifest_reopens_with_the_failure_as_a_comment
    with_home do |env|
      seed_clean(env)
      log = File.join(env['HOME'], 'rounds')
      editor = editor_script(env, 'two-step.sh', TWO_STEP.gsub('<log>', log))
      status, out, err = slipway('edit', 'project', 'clean', env: env.merge('EDITOR' => editor))

      assert_equal [0, "project/clean edited\n", ''], [status, out, err]
      rounds = File.read(log).split("---- round\n").drop(1)

      assert_equal 2, rounds.size
      assert_equal "# file will be reopened with the relevant failures.\n#\n" \
                   "# projects \"clean\" was not valid:\n# * \"spec.path\" must be a string\n#\nkind: Project\n",
                   rounds.last.lines[2..7].join
      assert_equal '~/dev/moved', table(slipway!('get', 'projects', '-o', 'wide', env:)).last[5]
    end
  end

  def test_declared_fields_reach_the_editor_and_a_bad_branch_reopens_the_file
    with_home do |env|
      seed(env, manifest('Project', 'clean', path: repo(env, 'clean'), remote: 'git@github.com:hvpaiva/clean.git',
                                             branch: 'main', paused: true))
      log = File.join(env['HOME'], 'rounds')
      editor = editor_script(env, 'branch.sh', BRANCH_TWO_STEP.gsub('<log>', log))
      status, out, err = slipway('edit', 'project', 'clean', env: env.merge('EDITOR' => editor))
      first, last = File.read(log).split("---- round\n").drop(1)

      assert_equal [0, "project/clean edited\n", ''], [status, out, err]
      assert_includes first, "spec:\n  path: \"~/dev/clean\"\n  remote: git@github.com:hvpaiva/clean.git\n  " \
                             "branch: main\n  paused: true\n"
      assert_includes last, "# * \"--track\" is not a valid branch name: #{Slipway::Git::BranchName::RULE}\n"
      assert_equal({ 'path' => '~/dev/clean', 'remote' => 'git@github.com:hvpaiva/clean.git', 'branch' => 'release/1.x',
                     'paused' => true },
                   Psych.safe_load(slipway!('get', 'project', 'clean', '-o', 'yaml', env:)).fetch('spec'))
    end
  end

  def test_kind_name_and_group_are_immutable
    with_home do |env|
      seed_clean(env)
      editor = editor_script(env, 'rename.sh', rewrite('$_.sub!(/^  name: clean/, "  name: renamed")'))
      status, out, err = slipway('edit', 'project', 'clean', env: env.merge('EDITOR' => editor))

      assert_equal [1, '', "error: Edit cancelled, no valid changes were saved.\n"], [status, out, err]
      assert_equal "project/clean\n", slipway!('get', 'projects', '-o', 'name', env:)
    end
  end

  def test_editor_precedence_is_slipway_editor_then_config_then_visual_then_editor
    with_home do |env|
      seed_clean(env)
      log = File.join(env['HOME'], 'editors')
      editors = %w[slipway config visual editor].to_h do |name|
        [name, editor_script(env, "#{name}.sh", %(echo #{name} >> "#{log}"))]
      end
      write_config(env, "editor: #{editors['config']}\n")
      env = env.merge('VISUAL' => editors['visual'], 'EDITOR' => editors['editor'])

      slipway('edit', 'project', 'clean', env: env.merge('SLIPWAY_EDITOR' => editors['slipway']))
      slipway('edit', 'project', 'clean', env:)
      write_config(env, '')
      slipway('edit', 'project', 'clean', env:)
      slipway('edit', 'project', 'clean', env: env.except('VISUAL'))

      assert_equal %w[slipway config visual editor], File.read(log).split
    end
  end

  def test_the_editor_line_is_split_like_a_shell_and_gets_the_file_last
    with_home do |env|
      seed_clean(env)
      log = File.join(env['HOME'], 'editors')
      visual = editor_script(env, 'visual.sh', %(echo "$@" >> "#{log}"))
      slipway('edit', 'project', 'clean', env: env.merge('VISUAL' => "#{visual} --wait", 'EDITOR' => '/nonexistent'))

      assert_match %r{\A--wait /\S+/slipway-edit-[^/]+/clean\.yaml\n\z}, File.read(log)
    end
  end

  def test_a_missing_editor_or_a_failing_one_is_an_error
    with_home do |env|
      seed_clean(env)
      failing = editor_script(env, 'fail.sh', 'exit 3')

      assert_equal [1, '', "error: editor \"/nonexistent/editor\" not found\n"],
                   slipway('edit', 'project', 'clean', env: env.merge('EDITOR' => '/nonexistent/editor'))
      assert_equal [1, '', "error: editor #{failing.inspect} exited with status 3\n"],
                   slipway('edit', 'project', 'clean', env: env.merge('EDITOR' => failing))
      assert_equal [1, '', "error: projects \"nothere\" not found\n"],
                   slipway('edit', 'project', 'nothere', env: env.merge('EDITOR' => failing))
    end
  end
end
