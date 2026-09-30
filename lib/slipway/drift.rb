# frozen_string_literal: true

require_relative 'git/url'

module Slipway
  # The ways a project can differ from its manifest, and the blockers that keep sync from
  # resolving them. Plan decides which apply; this module holds the words and their sentences.
  module Drift
    # +command+ is a git command line that shows or resolves the item; slipway prints it and never
    # runs it. Either can quote a URL git answered with, so both are redacted here, once for every
    # reader.
    Item = Data.define(:type, :message, :command, :blocker) do
      def initialize(type:, message:, command: nil, blocker: false)
        super(type:, message: Git::Url.redact(message), command: command && Git::Url.redact(command), blocker:)
      end
    end

    MISSING = 'Missing'
    REMOTE = 'Remote'
    BRANCH = 'Branch'
    REVISION = 'Revision'
    BEHIND = 'Behind'
    # In the order they are listed.
    TYPES = [MISSING, REMOTE, BRANCH, REVISION, BEHIND].freeze
    # The drift sync resolves by fast-forwarding the checked-out branch.
    MOVES = [REVISION, BEHIND].freeze

    # In the order Plan checks them. Each sentence says what holds sync back, so the line reads
    # the same in diff, describe and sync.
    BLOCKERS = {
      'NotARepo' => '%<path>s holds files but no repository; sync clones only into an absent directory',
      'Unsafe' => '%<reason>s',
      'Unknown' => '%<reason>s',
      'Detached' => 'HEAD is detached at %<head>s; sync never moves a detached HEAD',
      'Unborn' => 'no commits yet; nothing to fast-forward',
      'Gone' => 'upstream %<upstream>s no longer exists; sync never retargets a branch',
      'NoUpstream' => '%<branch>s tracks no upstream; sync fast-forwards only a tracking branch',
      'RevisionNotFound' => 'spec.revision %<revision>s is not in this repository; fetch it or unpin',
      'PastRevision' => '%<branch>s is past the pinned revision; sync never moves a branch back',
      'OffUpstream' => 'spec.revision %<revision>s is not on %<upstream>s; sync moves a branch only along its upstream',
      'Conflicted' => '%<paths>s; finish or abort the merge first',
      'Dirty' => '%<changes>s; sync fast-forwards only a tree without staged or unstaged changes',
      'Diverged' => '%<ahead>d ahead, %<behind>d behind %<upstream>s; sync never merges or rebases',
      'InProgress' => 'a %<operation>s is in progress'
    }.freeze

    def self.blocker(word, command: nil, **values)
      Item.new(type: word, message: format(BLOCKERS.fetch(word), **values), command:, blocker: true)
    end
  end
end
