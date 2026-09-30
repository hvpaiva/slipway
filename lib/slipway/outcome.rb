# frozen_string_literal: true

require_relative 'git'
require_relative 'state'

module Slipway
  # One project's result line in a verb that acts on each selected repository: `word` starts it,
  # `reason` follows in parentheses and `details` are printed under it as they are; the printer
  # redacts them and makes them plain.
  Outcome = Data.define(:project, :word, :reason, :details)

  class Outcome
    # The words more than one verb prints. A word only one verb prints stays with that verb.
    FETCHED = 'fetched'
    UNCHANGED = 'unchanged'
    SKIPPED = 'skipped'
    PAUSED = 'paused'
    DENIED = 'denied'
    FAILED = 'failed'
    ERROR_WORDS = { Git::AuthRequired => DENIED, Git::LocalUpstream => SKIPPED }.freeze
    REASONS = { Git::AuthRequired => 'AuthRequired', Git::LocalUpstream => 'LocalUpstream',
                Git::Timeout => 'Timeout', Git::WriteTimeout => 'Timeout',
                Git::ProtocolNotAllowed => 'ProtocolNotAllowed' }.freeze

    def initialize(project:, word:, reason: nil, details: []) = super

    # The line above already names the project, so the path is cut from the message.
    def self.failure(project, error)
      reason = REASONS.fetch(error.class) { State.for_error(error) }
      new(project:, word: ERROR_WORDS.fetch(error.class, FAILED), reason:,
          details: [detail(error), error.hint].compact)
    end

    # Nothing else in the result says which directory could not be read, so it leads the detail,
    # as the manifest writes it.
    def self.unreadable(project, inspection)
      error = inspection.error
      new(project:, word: SKIPPED, reason: inspection.state,
          details: ["#{project.path}: #{detail(error)}", error.hint].compact)
    end

    def self.detail(error) = error.message.delete_prefix("#{error.path}: ")
    private_class_method :detail
  end
end
