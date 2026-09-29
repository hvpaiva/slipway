# frozen_string_literal: true

require 'test_helper'

class ViewsProjectDeclaredTest < Minitest::Test
  include OutputHelper

  PROJECT = Slipway::Project.new(name: 'hldr', created_at: CommandsHelper::CREATED, path: '~/dev/hldr',
                                 description: 'Site', remote: 'git@github.com:h/hldr.git', branch: 'release/1.x',
                                 revision: CommandsHelper::SHA, sync_policy: 'FetchOnly', paused: true)
  INSPECTION = Slipway::Inspection.new(project: PROJECT, status: CommandsHelper::CLEAN, commit: nil, remote: nil,
                                       fetched_at: nil, state: 'Clean', error: nil)

  def test_describe_shows_the_declared_remote_branch_revision_policy_and_pause_before_the_status
    rendered = Slipway::Output::Describe.new(plain_context)
                                        .render(Slipway::Views::Project.describe(INSPECTION, now: CommandsHelper::NOW))

    assert_includes rendered, <<~TEXT
      Description:  Site
      Remote:       git@github.com:h/hldr.git
      Branch:       release/1.x
      Revision:     a1b2c3d (pinned)
      Sync Policy:  FetchOnly
      Paused:       true
      Status:       Clean
    TEXT
  end

  def test_object_carries_the_declared_fields_in_the_spec
    spec = Slipway::Views::Project.object(INSPECTION).fetch('spec')

    assert_equal({ 'path' => '~/dev/hldr', 'description' => 'Site', 'remote' => 'git@github.com:h/hldr.git',
                   'branch' => 'release/1.x', 'revision' => CommandsHelper::SHA, 'syncPolicy' => 'FetchOnly',
                   'paused' => true }, spec)
  end
end
