# frozen_string_literal: true

require 'psych'

module Slipway
  # The one YAML writer: manifests, `get -o yaml` and `config view` print the same dialect.
  module Yaml
    DOCUMENT_START = "---\n"

    # Dumps +hash+ with the restrictions of Psych.safe_dump, without folding long lines and
    # without the leading document marker, the way kubectl prints objects.
    def self.dump(hash) = Psych.safe_dump(hash, line_width: -1).delete_prefix(DOCUMENT_START)
  end
end
