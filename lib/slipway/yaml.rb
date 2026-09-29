# frozen_string_literal: true

require 'psych'

module Slipway
  # The one YAML writer: manifests, `get -o yaml` and `config view` print the same dialect.
  module Yaml
    DOCUMENT_START = "---\n"

    # line_width: -1 turns off Psych's line folding. The document marker is dropped, the way
    # kubectl prints objects.
    def self.dump(hash) = Psych.safe_dump(hash, line_width: -1).delete_prefix(DOCUMENT_START)
  end
end
