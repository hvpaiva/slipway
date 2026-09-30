# frozen_string_literal: true

require_relative 'cli/style'
require_relative 'output/age'
require_relative 'output/table'
require_relative 'output/describe'
require_relative 'output/explain'
require_relative 'output/serializer'

module Slipway
  module Output
    TABLE = 'table'
    WIDE = 'wide'
    NAME = 'name'
    # Help lists the formats in this order.
    FORMATS = [TABLE, WIDE, *Serializer::STRUCTURED, NAME].freeze

    # The rule lives in the command layer, whose runner prints the error lines and cannot
    # require Output.
    def self.plain(text) = CLI::Style.plain(text)

    # A warning can quote a manifest path or git's stderr. Every warning line is built here, and
    # the conventions test refuses the prefix anywhere else, so none reaches stderr raw.
    def self.warning(context, message)
      context.warn("#{context.paint_err(:warning, 'warning:')} #{plain(message)}")
    end
  end
end
