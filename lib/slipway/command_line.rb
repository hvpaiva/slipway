# frozen_string_literal: true

require 'shellwords'
require_relative 'paths'

module Slipway
  # The git command lines slipway prints for the user to run. Slipway never runs them.
  module CommandLine
    # Joins `words` as given, so a literal such as @{upstream}..HEAD prints as it is typed; a
    # caller quotes any word a manifest or git supplied, as Plan does.
    def self.git(project, *words) = ['git', '-C', path(project.path), *words].join(' ')

    # The path as the manifest writes it, so the line matches what was registered. Only the part
    # after ~ is quoted, since a shell does not expand a quoted ~.
    def self.path(path)
      rest = path.sub(Paths::TILDE, '')
      return Shellwords.escape(path) if rest == path

      rest.empty? ? '~' : "~#{Shellwords.escape(rest)}"
    end
  end
end
