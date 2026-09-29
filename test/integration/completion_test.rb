# frozen_string_literal: true

require 'test_helper'

class CompletionIntegrationTest < Minitest::Test
  include IntegrationHelper

  ROOT = <<~TEXT
    get\tDisplay one or many resources
    describe\tShow details of one or many resources
    create\tCreate a resource by name
    apply\tApply a configuration to a resource by file name or stdin
    delete\tDelete resources by type and name
    edit\tEdit a resource from the default editor
    label\tUpdate the labels on a resource
    config\tInspect the configuration in effect
    help\tHelp about any command
    version\tPrint the version of slipway
    completion\tOutput shell completion code for the specified shell (bash, zsh, fish)
    man\tShow the manual page of a command
    :4
  TEXT

  def test_completion_prints_the_script_of_the_shell
    with_home do |env|
      Slipway::CLI::CompletionScripts::SHELLS.each do |shell|
        script = File.read(File.join(GoldenHelper::FIXTURES, 'completion', "slipway.#{shell}"))

        assert_equal [0, script, ''], slipway('completion', shell, env:)
      end
    end
  end

  def test_the_shell_is_required_and_has_to_be_known
    with_home do |env|
      hint = "See 'slipway completion --help' for usage.\n"

      assert_equal [2, '', "error: missing required argument \"SHELL\"\n#{hint}"], slipway('completion', env:)
      assert_equal [2, '', "error: invalid argument \"tcsh\" for SHELL: must be one of bash, zsh, fish\n#{hint}"],
                   slipway('completion', 'tcsh', env:)
    end
  end

  def test_complete_lists_commands_with_their_summaries_at_the_root
    with_home do |env|
      status, out, err = slipway('__complete', '', env:)

      assert_equal [0, ''], [status, err]
      assert_equal ROOT, out
    end
  end

  def test_complete_offers_resource_names_from_the_store_minus_the_ones_typed
    with_home do |env|
      seed(env, manifest('Group', 'work'),
           manifest('Project', 'clean', path: '~/dev/clean'),
           manifest('Project', 'conflicted', path: '~/dev/conflicted'),
           manifest('Project', 'api', group: 'work', path: '~/dev/api'))

      assert_equal [0, "api\nclean\nconflicted\n:4\n", ''], slipway('__complete', 'get', 'projects', '', env:)
      assert_equal [0, "clean\nconflicted\n:4\n", ''], slipway('__complete', 'get', 'projects', 'c', env:)
      assert_equal [0, "conflicted\n:4\n", ''], slipway('__complete', 'get', 'projects', 'clean', 'c', env:)
      assert_equal [0, "default\nwork\n:4\n", ''], slipway('__complete', 'delete', 'groups', '', env:)
      assert_equal [0, "projects\tRegistered git repositories\ngroups\tNamespaces that hold projects\n:4\n", ''],
                   slipway('__complete', 'describe', '', env:)
    end
  end

  def test_complete_offers_flag_names_and_enum_values
    with_home do |env|
      assert_equal [0, "table\nwide\njson\nyaml\nname\n:4\n", ''], slipway('__complete', 'get', '-o', '', env:)
      assert_equal [0, "--output=json\n:4\n", ''], slipway('__complete', 'get', '--output=j', env:)
      assert_equal [0, "--color\tWhen to use color in the output; a bare --color means always.\n:4\n", ''],
                   slipway('__complete', '--col', env:)
      assert_equal [0, "bash\nzsh\nfish\n:4\n", ''], slipway('__complete', 'completion', '', env:)
    end
  end

  def test_complete_hands_file_names_to_the_shell_for_apply
    with_home do |env|
      assert_equal [0, ":0\n", ''], slipway('__complete', 'apply', '-f', '', env:)
      assert_equal [0, ":0\n", ''], slipway('__complete', 'apply', '--filename', 'a.yaml', '-f', 'b', env:)
    end
  end

  def test_complete_never_fails
    with_home do |env|
      assert_equal [0, ":4\n", ''], slipway('__complete', 'bogus', '', env:)
      assert_equal [0, ":4\n", ''], slipway('__complete', 'get', 'pods', '', env:)
      assert_equal [0, ":4\n", ''],
                   slipway('__complete', 'get', 'projects', '', env: env.merge('XDG_DATA_HOME' => '/dev/null/x'))
    end
  end

  def test_the_group_flag_completes_group_names_from_the_store
    with_home do |env|
      seed(env, manifest('Group', 'work'), manifest('Group', 'lab'))

      assert_equal [0, "lab\nwork\n:4\n", ''], slipway('__complete', '-n', '', env:)
      assert_equal [0, "--group=work\n:4\n", ''], slipway('__complete', 'get', 'projects', '--group=w', env:)
    end
  end
end
