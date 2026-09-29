# frozen_string_literal: true

module Slipway
  # The one-word STATUS shown for a project: the most actionable fact about its repository.
  module State
    WORDS = %w[Missing NotARepo Unsafe Conflicted Detached Unborn Dirty Gone Diverged Ahead Behind
               Clean Unknown].freeze

    ROLES = {
      'Clean' => :status_success,
      'Dirty' => :status_warning,
      'Ahead' => :status_warning,
      'Behind' => :status_warning,
      'Diverged' => :status_warning,
      'Detached' => :status_warning,
      'Gone' => :status_warning,
      'Unborn' => :status_warning,
      'Missing' => :status_danger,
      'NotARepo' => :status_danger,
      'Unsafe' => :status_danger,
      'Conflicted' => :status_danger,
      'Unknown' => :muted
    }.freeze

    # Reduces a Git::Status to one word. A conflict outranks everything, then the states in
    # which a commit could be lost, then uncommitted work, then the position against upstream.
    def self.derive(status)
      return 'Conflicted' if status.conflicted.positive?
      return 'Detached' if status.detached?
      return 'Unborn' if status.unborn?
      return 'Dirty' unless status.clean?
      return 'Gone' if status.upstream_gone?

      position(status)
    end

    # The word for a failure raised while reading a repository. Git problems that say
    # something about the path get their own word; anything else is Unknown.
    def self.for_error(error)
      case error
      when Git::MissingPath then 'Missing'
      when Git::NotARepository then 'NotARepo'
      when Git::UnsafeRepository then 'Unsafe'
      else 'Unknown'
      end
    end

    # The theme role that paints +word+ in a table.
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
