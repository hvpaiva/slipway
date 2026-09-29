# frozen_string_literal: true

require 'test_helper'
require 'yard'

# Every class and module under lib carries a comment, including the Data.define and
# Struct.new constants that Style/Documentation does not see.
class YardTest < Minitest::Test
  LIB = File.expand_path('../../lib', __dir__)

  def test_every_class_and_module_has_a_docstring
    namespaces = registry.all(:class, :module)

    assert_empty(namespaces.select { it.docstring.blank? }.map(&:path))
    assert_equal :class, registry.at('Slipway::Config::Document::Contents')&.type
    assert_operator namespaces.size, :>, 50
  end

  private

  def registry
    return YARD::Registry unless YARD::Registry.all.empty?

    YARD::Logger.instance.level = YARD::Logger::ERROR
    YARD.parse(File.join(LIB, '**', '*.rb'))
    YARD::Registry
  end
end
