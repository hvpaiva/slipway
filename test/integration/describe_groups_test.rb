# frozen_string_literal: true

require 'test_helper'

class DescribeGroupsIntegrationTest < Minitest::Test
  include IntegrationHelper

  GROUPS = <<~TEXT.freeze
    Name:         default
    Labels:       <none>
    Created:      #{CREATED}
    Age:          <age>
    Description:  <none>
    Projects:     1

    Name:         work
    Labels:       <none>
    Created:      #{CREATED}
    Age:          <age>
    Description:  Day job
    Projects:     1
  TEXT

  def test_groups_show_their_project_count
    with_home do |env|
      seed(env, manifest('Group', 'default'), manifest('Group', 'work', description: 'Day job'),
           manifest('Project', 'clean', path: repo(env, 'clean')),
           manifest('Project', 'api', group: 'work', path: repo(env, 'api', nil)))
      status, out, err = slipway('describe', 'groups', env:)

      assert_equal [0, ''], [status, err]
      assert_equal GROUPS, scrub_age(out)
      assert_equal out.lines[7..].join, slipway!('describe', 'group', 'work', env:)
    end
  end
end
