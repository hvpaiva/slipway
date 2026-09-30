# frozen_string_literal: true

require 'test_helper'

class ManifestListTest < Minitest::Test
  SOURCE = 'list.yaml'
  HLDR = { 'kind' => 'Project', 'metadata' => { 'name' => 'hldr' }, 'spec' => { 'path' => '~/dev/hldr' } }.freeze
  WORK = { 'kind' => 'Group', 'metadata' => { 'name' => 'work' } }.freeze

  def test_a_list_stands_for_its_items_in_order_among_the_other_documents
    list = Slipway::Yaml.dump({ 'kind' => 'List', 'items' => [WORK, HLDR] })
    text = "#{list}---\n#{Slipway::Yaml.dump(HLDR)}"

    assert_equal [WORK, HLDR, HLDR], Slipway::Manifest.load_objects(text, source: SOURCE)
    assert_empty Slipway::Manifest.load_objects("kind: List\nitems: []\n---\nkind: List\n", source: SOURCE)
  end

  def test_a_list_holds_only_items_and_every_item_is_a_mapping
    extra = load_error("kind: List\nmetadata: {}\nitems: []\n")
    scalar = load_error("kind: List\nitems:\n- kind: Group\n- 3\n")
    mapping = load_error("kind: List\nitems:\n  a: 1\n")

    assert_equal "#{SOURCE}: unknown field \"metadata\" in a List", extra.message
    assert_equal "#{SOURCE}: \"items\" of a List must be a sequence of mappings", scalar.message
    assert_equal scalar.message, mapping.message
  end

  def test_the_documents_of_one_manifest_are_not_expanded
    error = assert_raises(Slipway::Manifest::Invalid) do
      Slipway::Manifest.parse_yaml("kind: List\nitems:\n- {kind: Group, metadata: {name: work}}\n", source: SOURCE)
    end

    assert_equal "#{SOURCE}: \"kind\" must be Project or Group, not \"List\"", error.message
  end

  private

  def load_error(text)
    assert_raises(Slipway::Manifest::Invalid) { Slipway::Manifest.load_objects(text, source: SOURCE) }
  end
end
