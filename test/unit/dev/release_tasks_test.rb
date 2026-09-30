# frozen_string_literal: true

require 'open3'
require 'test_helper'

class ReleaseTasksTest < Minitest::Test
  ROOT = File.expand_path('../../..', __dir__)
  PUBLISHING = %w[release:guard_clean release:source_control_push release:rubygem_push].freeze
  # Unset, so the tasks run as on a maintainer's machine even when the suite runs in GitHub Actions.
  LOCAL = { 'GITHUB_ACTIONS' => nil, 'GITHUB_REF_TYPE' => nil, 'GITHUB_OUTPUT' => nil, 'TAG' => nil }.freeze

  # In a child process: ContributingTest already loaded the Rakefile, and loading it again would
  # redefine its constants.
  def rake(*)
    Open3.capture3(LOCAL, RbConfig.ruby, '-rrake', '-e', 'Rake.application.run', '--', *, chdir: ROOT)
  end

  def test_every_task_that_tags_or_pushes_runs_the_guard
    out, err, status = rake('-P')

    assert_predicate status, :success?, err
    prerequisites = out.split(/^rake /).drop(1).to_h { [it.split.first, it.split.drop(1)] }
    PUBLISHING.each { assert_includes prerequisites.fetch(it), 'release:guard_ci', it }
  end

  def test_the_guard_refuses_outside_github_actions
    _, err, status = rake('release:guard_ci')

    refute_predicate status, :success?
    assert_equal "rake release runs only inside GitHub Actions; use bin/release\n", err
  end

  def test_verify_passes_on_this_checkout_without_a_tag
    out, err, status = rake('release:verify')

    assert_predicate status, :success?, err
    assert_match(/\Arelease:verify: no tag given, Slipway::VERSION \S+ and CHANGELOG.md agree\n\z/, out)
  end
end
