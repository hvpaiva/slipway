# frozen_string_literal: true

module Slipway
  module Git
    module Url
      # The userinfo runs to the last "@" before the authority ends, so a password holding a raw
      # "@" is covered whole.
      USERINFO = %r{(?<scheme>[A-Za-z][A-Za-z0-9+.-]*)://(?<userinfo>[^\s/?#]+)@}
      # Over http a token is often sent as the user name, so the whole userinfo is secret there,
      # and in a scheme that carries http, such as git+https or persistent-https.
      WHOLE_USERINFO = /(?:\A|[+-])https?\z/i
      MASK = '***'

      # +text+ is free text, such as a line of git's stderr: only scheme://userinfo@ URLs change,
      # so scp-like addresses (git@host:path) and e-mail addresses stay as they are.
      def self.redact(text)
        text.gsub(USERINFO) do
          match = Regexp.last_match
          "#{match[:scheme]}://#{mask(match[:scheme], match[:userinfo])}@"
        end
      end

      def self.mask(scheme, userinfo)
        return MASK if WHOLE_USERINFO.match?(scheme)

        user, colon, = userinfo.partition(':')
        colon.empty? ? userinfo : "#{user}:#{MASK}"
      end

      private_class_method :mask
    end
  end
end
