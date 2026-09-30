# frozen_string_literal: true

require 'test_helper'

class APIResourcesTest < Minitest::Test
  include CommandsHelper

  TABLE = <<~TABLE
    NAME       SHORTNAMES   KIND      GROUPED
    groups     <none>       Group     false
    projects   proj         Project   true
  TABLE
  # Without the header row, SHORTNAMES and GROUPED narrow to their widest cell.
  TABLE_ROWS = <<~TABLE
    groups     <none>   Group     false
    projects   proj     Project   true
  TABLE
  HINT = "See 'slipway api-resources --help' for usage.\n"

  def test_lists_every_resource_type_sorted_by_name
    with_sandbox do |env|
      assert_equal [0, TABLE, ''], run_cli('api-resources', env:)
      assert_equal [0, TABLE, ''], run_cli('api-resources', '-o', 'table', env:)
    end
  end

  def test_name_prints_the_plural_names
    with_sandbox do |env|
      assert_equal [0, "groups\nprojects\n", ''], run_cli('api-resources', '-o', 'name', env:)
      assert_equal [0, "groups\nprojects\n", ''], run_cli('api-resources', '-o', 'name', '--no-headers', env:)
    end
  end

  def test_no_headers_drops_the_header_row
    with_sandbox do |env|
      assert_equal [0, TABLE_ROWS, ''], run_cli('api-resources', '--no-headers', env:)
    end
  end

  def test_the_resources_registered_change_nothing
    with_runtime do |runtime|
      register_group(runtime, 'work')
      register(runtime, 'hldr', group: 'work')

      assert_equal [0, TABLE, ''], run_cli('api-resources', env: runtime.env, runtime:)
    end
  end

  def test_the_structured_formats_are_refused
    with_sandbox do |env|
      %w[json yaml].each do |format|
        refusal = "error: invalid argument #{format.inspect} for --output: must be one of table, name\n"

        assert_equal [2, '', "#{refusal}#{HINT}"], run_cli('api-resources', '-o', format, env:)
      end
    end
  end

  def test_takes_no_arguments
    with_sandbox do |env|
      assert_equal [2, '', "error: unexpected argument \"projects\"\n#{HINT}"],
                   run_cli('api-resources', 'projects', env:)
    end
  end
end
