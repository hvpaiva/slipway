# frozen_string_literal: true

require 'test_helper'

class PipeIntegrationTest < Minitest::Test
  include IntegrationHelper

  # Enough projects for the yaml listing to outgrow the pipe buffer, so the write after
  # head exits fails with EPIPE.
  PROJECTS = 400

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

  def test_a_write_verb_finishes_its_work_when_the_reader_goes_away
    with_home do |env|
      names = (1..PROJECTS).map { "p#{it}" }
      seed(env, manifest('Group', 'many'), *names.map { manifest('Project', it, group: 'many', path: "~/x/#{it}") })
      script = %("$@" | head -c1 >/dev/null; printf 'status=%s\\n' "${PIPESTATUS[0]}")
      out, err, status = Open3.capture3(env, 'bash', '-c', script, 'pipe', *COMMAND, 'delete', 'projects', '-n', 'many',
                                        *names, unsetenv_others: true)

      assert_equal [0, "status=0\n", ''], [status.exitstatus, out, err]
      assert_equal [0, '', "No resources found in many group.\n"], slipway('get', 'projects', '-n', 'many', env:)
    end
  end

  def test_a_closed_stderr_keeps_the_exit_status_of_the_error
    with_home do |env|
      script = %("$@" 2>&-; echo "status=$?")
      out, _, status = Open3.capture3(env, 'bash', '-c', script, 'closed', *COMMAND, 'get', 'project', 'nope',
                                      unsetenv_others: true)
      usage, = Open3.capture3(env, 'bash', '-c', script, 'closed', *COMMAND, 'get', '--bogus', unsetenv_others: true)

      assert_equal [0, "status=1\n"], [status.exitstatus, out]
      assert_equal "status=2\n", usage
    end
  end
end
