# frozen_string_literal: true

module Slipway
  # A repository can be dirty and behind at once; the STATUS column shows one word, for the
  # fact that needs attention first.
  module State
    # In precedence order.
    ROLES = {
      'Missing' => :status_danger,
      'NotARepo' => :status_danger,
      'Unsafe' => :status_danger,
      'Conflicted' => :status_danger,
      'Detached' => :status_warning,
      'Unborn' => :status_warning,
      'Dirty' => :status_warning,
      'Gone' => :status_warning,
      'Diverged' => :status_warning,
      'Ahead' => :status_warning,
      'Behind' => :status_warning,
      'Clean' => :status_success,
      'Unknown' => :muted
    }.freeze

    # A conflict outranks everything, then the states in which a commit could be lost, then
    # uncommitted work, then the position against upstream.
    def self.derive(status)
      return 'Conflicted' if status.conflicted.positive?
      return 'Detached' if status.detached?
      return 'Unborn' if status.unborn?
      return 'Dirty' unless status.clean?
      return 'Gone' if status.upstream_gone?

      position(status)
    end

    def self.for_error(error)
      case error
      when Git::MissingPath then 'Missing'
      when Git::NotARepository then 'NotARepo'
      when Git::UnsafeRepository then 'Unsafe'
      else 'Unknown'
      end
    end

    def self.role(word) = ROLES.fetch(word)

    def self.position(status)
      ahead = status.ahead.to_i.positive?
      behind = status.behind.to_i.positive?
      return 'Diverged' if ahead && behind
      return 'Ahead' if ahead
      return 'Behind' if behind

      'Clean'
    end
    private_class_method :position
  end
end
