# frozen_string_literal: true

require 'test_helper'

class APIResourcesIntegrationTest < Minitest::Test
  include IntegrationHelper

  TABLE = <<~TABLE
    NAME       SHORTNAMES   KIND      GROUPED
    groups     <none>       Group     false
    projects   proj         Project   true
  TABLE
  WIDE = <<~TABLE
    NAME       SHORTNAMES   KIND      GROUPED   VERBS
    groups     <none>       Group     false     apply,create,delete,describe,edit,get,label
    projects   proj         Project   true      apply,create,delete,describe,diff,edit,fetch,get,label,rollout,sync
  TABLE

  def test_prints_the_resource_types_in_each_format
    with_home do |env|
      assert_equal [0, TABLE, ''], slipway('api-resources', env:)
      assert_equal [0, WIDE, ''], slipway('api-resources', '-o', 'wide', env:)
      assert_equal [0, "groups\nprojects\n", ''], slipway('api-resources', '-o', 'name', env:)
    end
  end

  def test_every_name_it_prints_is_a_type_word_get_accepts
    with_home do |env|
      rows = slipway!('api-resources', '--no-headers', env:).lines.map(&:split)
      words = rows.flat_map { |name, shortnames| [name, *shortnames.split(',')] } - [Slipway::Output::Table::NONE]

      assert_equal %w[groups projects proj], words
      words.each { assert_equal 0, slipway('get', it, env:).first, it }
    end
  end

  def test_every_kind_it_prints_is_the_kind_the_manifests_of_its_type_declare
    with_home do |env|
      slipway!('create', 'project', 'hldr', '--path', env.fetch('HOME'), env:)

      slipway!('api-resources', '--no-headers', env:).lines.map(&:split).each do |name, _, kind|
        items = Psych.safe_load(slipway!('get', name, '-o', 'yaml', env:)).fetch('items')

        assert_equal [kind], items.map { it.fetch('kind') }.uniq, name
      end
    end
  end

  def test_json_is_refused_with_the_formats_it_prints
    with_home do |env|
      assert_equal [2, '', "error: invalid argument \"json\" for --output: must be one of table, wide, name\n" \
                           "See 'slipway api-resources --help' for usage.\n"],
                   slipway('api-resources', '-o', 'json', env:)
    end
  end
end
