# frozen_string_literal: true

require_relative 'git/runner'

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

    # What each word means, in the same order. The help of get and describe prints these, and the
    # README table says the same with its code spans marked.
    MEANINGS = {
      'Missing' => 'The registered path is relative, or is not a directory on this machine.',
      'NotARepo' => 'The directory exists but no repository contains it.',
      'Unsafe' => 'git refused the repository because another user owns it (safe.directory); describe, diff and ' \
                  'fetch print the git command that trusts it.',
      'Conflicted' => 'The working tree has unmerged paths.',
      'Detached' => 'HEAD points at a commit rather than a branch.',
      'Unborn' => 'The branch has no commits yet.',
      'Dirty' => 'Staged, modified or untracked files are present.',
      'Gone' => 'An upstream is configured but its remote-tracking ref is gone, as of the last fetch --prune (or a ' \
                'fetch with fetch.prune set).',
      'Diverged' => 'The branch is both ahead of and behind its upstream, as of the last fetch (FETCHED).',
      'Ahead' => 'Commits not yet pushed to the upstream, as of the last fetch (FETCHED).',
      'Behind' => 'Commits on the upstream not yet pulled, as of the last fetch (FETCHED).',
      'Clean' => 'Nothing to do.',
      'Unknown' => 'git could not answer: it is not installed, it did not finish within ' \
                   "#{Git::Runner::DEFAULT_TIMEOUT.to_i} seconds, or it failed for a reason slipway does not " \
                   'classify. Each distinct reason is printed once on stderr per run.'
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
