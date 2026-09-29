# frozen_string_literal: true

module Slipway
  module Git
    # What `git status` says about one working tree: branch and upstream position plus the
    # counts of staged, unstaged, untracked and conflicted entries and of stashes.
    Status = Data.define(:branch, :head, :upstream, :ahead, :behind, :upstream_gone,
                         :staged, :unstaged, :untracked, :conflicted, :stashes) do
      # Parses the output of `git status --porcelain=v2 --branch --show-stash -z`.
      def self.parse(text) = Porcelain.new.parse(text)

      def initialize(head:, branch: 'main', upstream: nil, ahead: nil, behind: nil, upstream_gone: false,
                     staged: 0, unstaged: 0, untracked: 0, conflicted: 0, stashes: 0)
        super
      end

      # HEAD points at a commit rather than a branch.
      def detached? = branch.nil?

      # The branch has no commits yet.
      def unborn? = head.nil?

      # An upstream is configured but its ref no longer exists.
      def upstream_gone? = upstream_gone

      # Nothing staged, modified, untracked or conflicted; stashes do not count.
      def clean? = staged.zero? && unstaged.zero? && untracked.zero? && conflicted.zero?
    end

    # Reads one porcelain v2 document, NUL separated, into the fields of a Status.
    class Porcelain
      INITIAL = '(initial)'
      DETACHED = '(detached)'
      # Porcelain prints the full object id; the table shows what `git log --oneline` would.
      ABBREVIATION = 7
      UNCHANGED = '.'

      def initialize
        @branch = nil
        @head = nil
        @upstream = nil
        @ahead = nil
        @behind = nil
        @position_seen = false
        @stashes = 0
        @counts = Hash.new(0)
      end

      def parse(text)
        records = text.split("\0")
        until records.empty?
          record = records.shift
          # A rename or copy record is followed by the original path as its own field.
          records.shift if record.start_with?('2 ')
          consume(record)
        end
        status
      end

      private

      def status
        Status.new(branch: @branch, head: @head, upstream: @upstream, ahead: @ahead, behind: @behind,
                   upstream_gone: !@upstream.nil? && !@position_seen,
                   staged: @counts[:staged], unstaged: @counts[:unstaged],
                   untracked: @counts[:untracked], conflicted: @counts[:conflicted], stashes: @stashes)
      end

      def consume(record)
        case record
        when /\A# / then header(record)
        when /\A[12] / then change(record[2], record[3])
        when /\Au / then @counts[:conflicted] += 1
        when /\A\? / then @counts[:untracked] += 1
        end
      end

      def header(record)
        key, value = record.delete_prefix('# ').split(' ', 2)
        if key == 'stash'
          @stashes = Integer(value)
        elsif key.start_with?('branch.')
          branch(key.delete_prefix('branch.'), value)
        end
      end

      def branch(field, value)
        case field
        when 'oid' then @head = value[0, ABBREVIATION] unless value == INITIAL
        when 'head' then @branch = value unless value == DETACHED
        when 'upstream' then @upstream = value
        when 'ab' then position(value)
        end
      end

      # `+<ahead> -<behind>`; git prints `+? -?` when it was told not to count.
      def position(value)
        @position_seen = true
        @ahead, @behind = value.split.map { count(it) }
      end

      def count(token)
        digits = token.delete_prefix('+').delete_prefix('-')
        digits == '?' ? nil : Integer(digits)
      end

      def change(index, worktree)
        @counts[:staged] += 1 unless index == UNCHANGED
        @counts[:unstaged] += 1 unless worktree == UNCHANGED
      end
    end
  end
end
