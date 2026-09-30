# frozen_string_literal: true

require_relative 'git/url'

module Slipway
  # The ways a project can differ from its manifest, and the blockers that keep sync from
  # resolving them. Plan decides which apply; this module holds the words and their sentences.
  module Drift
    # `command` is a git command line that shows or resolves the item; slipway prints it and never
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
    # When each type is reported, in the same order. The help of diff prints these, and the README
    # table says the same with its code spans marked.
    TYPE_MEANINGS = {
      MISSING => 'The registered path is relative or is not a directory. For a path that is not a directory, a ' \
                 'project with spec.remote shows the git clone command that recreates it.',
      REMOTE => 'origin is absent or differs from spec.remote. Sync never changes a remote.',
      BRANCH => 'HEAD is detached or on another branch than spec.branch. Sync never switches branches.',
      REVISION => 'HEAD is not the commit spec.revision pins. The pin replaces the upstream, so a pinned project is ' \
                  'never Behind; under FastForward sync will fast-forward a branch behind the pin to it unless a ' \
                  'blocker stops it, and never moves a branch back.',
      BEHIND => 'The checked-out branch is behind its upstream. Under FastForward sync will fast-forward it unless a ' \
                'blocker stops it; under FetchOnly, or while spec.paused is true, it is only reported.'
    }.freeze
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

    # What each blocker means, in the same order, for the help of diff and the README table.
    BLOCKER_MEANINGS = {
      'NotARepo' => 'The directory exists but holds no repository.',
      'Unsafe' => 'git refused the repository because another user owns it (safe.directory); the git command that ' \
                  'trusts it follows.',
      'Unknown' => 'git could not answer; the reason is also printed once on stderr.',
      'Detached' => 'HEAD points at a commit rather than a branch.',
      'Unborn' => 'The branch has no commits yet.',
      'Gone' => 'The upstream is configured but its ref no longer exists.',
      'NoUpstream' => 'The branch tracks no upstream.',
      'RevisionNotFound' => 'The repository has no commit by the name spec.revision pins.',
      'PastRevision' => 'HEAD is past the pinned commit or on another line of history, so reaching the pin would ' \
                        'move the branch back.',
      'OffUpstream' => 'The upstream does not hold the pinned commit, which may be on another branch or a fork; sync ' \
                       'moves a branch only along its upstream.',
      'Conflicted' => 'The branch is behind and the working tree has unmerged paths.',
      'Dirty' => 'The branch is behind and has staged or unstaged changes; untracked files do not block.',
      'Diverged' => 'The branch is behind and has commits of its own.',
      'InProgress' => 'The branch would be fast-forwarded, but a merge, rebase, cherry-pick, revert, bisect or ' \
                      'git am is in progress.'
    }.freeze

    def self.blocker(word, command: nil, **values)
      Item.new(type: word, message: format(BLOCKERS.fetch(word), **values), command:, blocker: true)
    end
  end
end
