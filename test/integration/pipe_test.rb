# frozen_string_literal: true

require 'test_helper'

class PipeIntegrationTest < Minitest::Test
  include IntegrationHelper

  # Enough projects for the yaml listing to outgrow the pipe buffer, so the write after
  # head exits fails with EPIPE.
  PROJECTS = 300

  def test_a_closed_pipe_ends_the_run_quietly_with_status_zero
    with_home do |env|
      seed(env, manifest('Group', 'many'),
           *(1..PROJECTS).map { manifest('Project', "p#{it}", group: 'many', path: "~/nowhere/p#{it}") })
      script = %("$@" | head -1; printf 'status=%s\\n' "${PIPESTATUS[0]}")
      out, err, status = Open3.capture3(env, 'bash', '-o', 'pipefail', '-c', script, 'pipe', *COMMAND, 'get',
                                        'projects', '-n', 'many', '-o', 'yaml', unsetenv_others: true)

      assert_equal [0, "kind: List\nstatus=0\n", ''], [status.exitstatus, out, err]
      assert_operator slipway!('get', 'projects', '-n', 'many', '-o', 'yaml', env:).bytesize, :>, 65_536
    end
  end
end
