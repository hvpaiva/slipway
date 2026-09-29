# frozen_string_literal: true

require_relative 'output/age'
require_relative 'output/table'
require_relative 'output/describe'
require_relative 'output/serializer'

module Slipway
  # Renderers for the kubectl-shaped output formats: tables, describe blocks, JSON and YAML.
  module Output
    TABLE = 'table'
    WIDE = 'wide'
    NAME = 'name'
    # Every value -o accepts, in the order help lists them.
    FORMATS = [TABLE, WIDE, *Serializer::STRUCTURED, NAME].freeze
    # C0 and C1 control characters and DEL: everything a terminal would obey instead of show.
    CONTROL = /[\x00-\x1F\x7F\u0080-\u009F]/
    REPLACEMENT = "\uFFFD"

    # +text+ with every control character made visible, so a commit subject or a manifest
    # field can neither move the cursor nor paint a STATUS of its own. C0 characters take
    # caret notation (ESC is ^[), C1 characters the replacement character.
    def self.plain(text)
      text.to_s.scrub.gsub(CONTROL) { |char| char.ord < 0x80 ? "^#{((char.ord + 0x40) & 0x7F).chr}" : REPLACEMENT }
    end
  end
end
