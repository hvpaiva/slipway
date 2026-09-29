# frozen_string_literal: true

require_relative 'views/project'
require_relative 'views/group'

module Slipway
  # Turns resources into what the renderers print: table headers and rows, describe entries
  # and the object Hash that json and yaml emit. One module per kind, no I/O.
  module Views
  end
end
