# frozen_string_literal: true

require 'test_helper'

class GetFormatsIntegrationTest < Minitest::Test
  include IntegrationHelper
  include GetRegistry

  CLEAN_JSON = <<~TEXT.freeze
    {
      "kind": "Project",
      "metadata": {
        "name": "clean",
        "group": "default",
        "labels": {
          "lang": "rust"
        },
        "creationTimestamp": "#{CREATED}"
      },
      "spec": {
        "path": "~/dev/clean",
        "description": "A clean one"
      },
      "status": {
        "branch": "main",
        "head": "#{HEAD}",
        "staged": 0,
        "unstaged": 0,
        "untracked": 0,
        "conflicted": 0,
        "stashes": 0,
        "state": "Clean",
        "drift": [
          {
            "type": "NoUpstream",
            "message": "main tracks no upstream; sync fast-forwards only a tracking branch",
            "blocker": true
          }
        ],
        "lastCommit": {
          "hash": "#{SHA}",
          "author": "Fixture",
          "email": "fixture@example.com",
          "date": "2023-11-14T22:13:20Z",
          "subject": "initial commit"
        }
      }
    }
  TEXT

  CLEAN_AND_PLAIN_YAML = <<~TEXT.freeze
    kind: List
    items:
    - kind: Project
      metadata:
        name: clean
        group: default
        labels:
          lang: rust
        creationTimestamp: '#{CREATED}'
      spec:
        path: "~/dev/clean"
        description: A clean one
      status:
        branch: main
        head: #{HEAD}
        staged: 0
        unstaged: 0
        untracked: 0
        conflicted: 0
        stashes: 0
        state: Clean
        drift:
        - type: NoUpstream
          message: main tracks no upstream; sync fast-forwards only a tracking branch
          blocker: true
        lastCommit:
          hash: #{SHA}
          author: Fixture
          email: fixture@example.com
          date: '2023-11-14T22:13:20Z'
          subject: initial commit
    - kind: Project
      metadata:
        name: plain
        group: default
        labels: {}
        creationTimestamp: '#{CREATED}'
      spec:
        path: "~/dev/plain"
      status:
        state: NotARepo
        drift:
        - type: NotARepo
          message: "~/dev/plain holds files but no repository; sync clones only into an absent directory"
          blocker: true
  TEXT

  WORK_JSON = <<~TEXT.freeze
    {
      "kind": "Group",
      "metadata": {
        "name": "work",
        "labels": {},
        "creationTimestamp": "#{CREATED}"
      },
      "spec": {
        "description": "Day job"
      },
      "status": {
        "projects": 2
      }
    }
  TEXT

  def test_name_output_prints_type_slash_name
    with_home do |env|
      registry(env)
      status, out, err = slipway('get', 'projects', '-o', 'name', '-A', env:)

      assert_equal 0, status
      assert_empty err
      assert_equal "project/clean\nproject/dirty\nproject/gone\nproject/plain\nproject/ahead\nproject/detached\n", out
      assert_equal "group/default\ngroup/work\n", slipway!('get', 'groups', '-o', 'name', env:)
    end
  end

  def test_json_of_one_project_is_the_object_with_its_status
    with_home do |env|
      registry(env)
      status, out, err = slipway('get', 'project', 'clean', '-o', 'json', env:)

      assert_equal [0, ''], [status, err]
      assert_equal CLEAN_JSON, out
    end
  end

  def test_yaml_of_several_projects_is_a_list
    with_home do |env|
      registry(env)
      status, out, err = slipway('get', 'projects', 'clean', 'plain', '-o', 'yaml', env:)

      assert_equal [0, ''], [status, err]
      assert_equal CLEAN_AND_PLAIN_YAML, out
    end
  end

  def test_groups_carry_their_project_count
    with_home do |env|
      registry(env)
      _, out, = slipway('get', 'groups', env:)
      _, wide, = slipway('get', 'groups', '-o', 'wide', env:)

      assert_table [%w[NAME PROJECTS AGE], ['default', '4', :age], ['work', '2', :age]], out
      assert_table [%w[NAME PROJECTS AGE DESCRIPTION], ['default', '4', :age, '<none>'],
                    ['work', '2', :age, 'Day job']], wide
      assert_equal WORK_JSON, slipway!('get', 'group', 'work', '-o', 'json', env:)
    end
  end

  def test_type_words_have_singular_and_short_forms
    with_home do |env|
      registry(env)

      %w[projects project proj].each do |word|
        assert_equal "project/clean\n", slipway!('get', word, 'clean', '-o', 'name', env:)
      end
      %w[groups group].each do |word|
        assert_equal "group/work\n", slipway!('get', word, 'work', '-o', 'name', env:)
      end
    end
  end
end
