# frozen_string_literal: true

# Loaded with -r into each slipway the README examples run. Ruby writes stdout at once to a
# terminal but holds it in a pipe until exit, which would put every stdout line after stderr.
$stdout.sync = true
