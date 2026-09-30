# frozen_string_literal: true

require_relative '../error'

module Slipway
  module Git
    # Remote URLs: the forms slipway accepts (validate!, valid?) and the masking of credentials
    # in any text that may quote one (redact).
    module Url
      # Callers decide whether the URL came from the command line or a file.
      class Invalid < Slipway::Error; end

      # The userinfo runs to the last "@" before the authority ends, so a password holding a raw
      # "@" is covered whole.
      USERINFO = %r{(?<scheme>[A-Za-z][A-Za-z0-9+.-]*)://(?<userinfo>[^\s/?#]+)@}
      # Over http a token is often sent as the user name, so the whole userinfo is secret there,
      # and in a scheme that carries http, such as git+https or persistent-https.
      WHOLE_USERINFO = /(?:\A|[+-])https?\z/i
      LEADING_USERINFO = /\A#{USERINFO}/
      MASK = '***'

      MAX = 2048
      TEXT = /\A[^\p{C}\p{Z}]+\z/
      HOST = /[A-Za-z0-9][A-Za-z0-9.-]*/
      USER = /[A-Za-z0-9_][A-Za-z0-9._-]*/
      # git reads "<name>::" as a transport helper and "<name>://" as a URL, so an scp-like path
      # starting with either is not a path.
      FORMS = [
        %r{\A(?:ssh|https?|git)://(?:#{USER}@)?#{HOST}(?::\d{1,5})?/},
        %r{\Afile://(?:#{HOST})?/},
        %r{\A(?:#{USER}@)?#{HOST}:(?!:|//).}
      ].freeze
      # git takes "user:secret@host:path" as the host "user", but whoever reads it sees a password.
      SCP_PASSWORD = %r{\A[^/@]*:(?!//)[^@]*@}
      # A password holding "/", "?", "#" or whitespace ends the userinfo early for #redact and
      # makes the remote invalid, so it is caught only once the remote is refused. A token before
      # the "@" has no ":" to tell it from a user name, so a refused remote with an "@" past its
      # scheme is never quoted.
      URL_PASSWORD = %r{\A[A-Za-z][A-Za-z0-9+.-]*://[^@:/]*:.*@}m
      AFTER_SCHEME_AT = %r{://[^@]*@}
      RULE = 'scheme://host/path with scheme ssh, https, http, git or file, or [user@]host:path, where the ' \
             'host is letters, digits, dots and dashes starting with a letter or digit; at most 2048 characters, ' \
             'without whitespace or control characters'
      CREDENTIALS = 'must not embed credentials; use a credential helper'

      # `text` is free text, such as a line of git's stderr: only scheme://userinfo@ URLs change,
      # so scp-like addresses (git@host:path) and e-mail addresses stay as they are.
      def self.redact(text)
        text.gsub(USERINFO) do
          match = Regexp.last_match
          "#{match[:scheme]}://#{mask(match[:scheme], match[:userinfo])}@"
        end
      end

      # Drops what #redact would mask, so a remote read from a clone keeps its address and a
      # credential helper supplies what was dropped.
      def self.without_credentials(url)
        url.sub(LEADING_USERINFO) do
          match = Regexp.last_match
          user = WHOLE_USERINFO.match?(match[:scheme]) ? '' : match[:userinfo].partition(':').first
          user.empty? ? "#{match[:scheme]}://" : "#{match[:scheme]}://#{user}@"
        end
      end

      # A remote is accepted only when #redact would leave it as it is, so describe, json and
      # yaml can print it whole. The command line may label UTF-8 bytes as US-ASCII in the C
      # locale, so the value is read, and returned, as UTF-8.
      def self.validate!(url, field:)
        text = url.dup.force_encoding(Encoding::UTF_8)
        shown = text.scrub
        raise Invalid, "#{field} #{CREDENTIALS}" if credentials?(shown)
        return text if valid?(text)
        raise Invalid, "#{field} #{CREDENTIALS}" if URL_PASSWORD.match?(shown)

        quoted = AFTER_SCHEME_AT.match?(shown) ? field : shown.inspect
        raise Invalid, "#{quoted} is not a valid remote URL: #{RULE}"
      end

      def self.mask(scheme, userinfo)
        return MASK if WHOLE_USERINFO.match?(scheme)

        user, colon, = userinfo.partition(':')
        colon.empty? ? userinfo : "#{user}:#{MASK}"
      end

      def self.credentials?(text) = redact(text) != text || SCP_PASSWORD.match?(text)

      def self.valid?(text)
        text.valid_encoding? && text.size <= MAX && TEXT.match?(text) && FORMS.any? { it.match?(text) }
      end

      private_class_method :mask, :credentials?, :valid?
    end
  end
end
