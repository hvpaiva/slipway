# frozen_string_literal: true

require 'open3'

module Commits
  BASE = 'origin/main'
  TYPES = %w[feat fix docs test refactor chore ci].freeze
  # Dependabot puts "[security] " between the prefix and the summary of a security update.
  SUBJECT = /\A(#{TYPES.join('|')})(\([a-z0-9-]+\))?!?: (\[security\] )?[a-z]/
  UNFINISHED = /\A(fixup!|squash!|amend!|wip\b)|\A\w+(\([a-z0-9-]+\))?!?:\s*wip\b/i
  # git revert writes this subject, and Reapply when the reverted commit was itself a revert.
  REVERT = /\A(?:Revert|Reapply) "(?<subject>.+)"\z/
  ASSISTANTS = %w[claude anthropic copilot cursor codex chatgpt gpt- gemini assistant].freeze
  # These keys only ever name a tool. Ruby's ^ already anchors at every line, and /m would let
  # .* run past the end of the trailer into later lines, so the pattern is case-insensitive only.
  TOOL_TRAILER = /^(Generated-(by|with)|Assisted-by|Claude-Session):.*\b(#{ASSISTANTS.join('|')})\b/i
  # A human co-author can share an assistant's name, as Claude Monet does, so a Co-Authored-By
  # trailer is judged by its address: the fixed ones assistants and GitHub apps write.
  CO_AUTHOR = /^Co-Authored-By:[^<\n]*<(?<address>[^>\n]+)>/i
  BOT_ADDRESS = /\A(noreply@anthropic\.com|cursoragent@cursor\.com|(aider|noreply)@aider\.chat|
                    \d+\+(Copilot|[\w-]+\[bot\])@users\.noreply\.github\.com)\z/ix
  GENERATED_WITH = /^\W*Generated with \[?Claude/i

  Commit = Data.define(:sha, :parents, :message) do
    def subject = message.lines.first.to_s.chomp
    def merge? = parents.size > 1
  end

  class Error < StandardError; end

  module_function

  def read(range, chdir: Dir.pwd)
    out, err, status = Open3.capture3('git', 'log', '--no-show-signature', '--reverse', '-z',
                                      '--format=%h%x1f%p%x1f%B', range, '--', chdir:)
    raise Error, "git log #{range} failed: #{utf8(err).strip}" unless status.success?

    utf8(out).split("\0").map do |record|
      sha, parents, message = record.split("\x1f", 3)
      Commit.new(sha:, parents: parents.to_s.split, message: message.to_s)
    end
  end

  # [range, nil] when HEAD has commits that +base+ lacks, otherwise [nil, why nothing is linted].
  def branch_range(base = BASE, chdir: Dir.pwd)
    return [nil, "no #{base} to compare HEAD with"] unless commit?(base, chdir:)

    range = "#{base}..HEAD"
    return [nil, "HEAD has no commits that #{base} lacks"] if read(range, chdir:).empty?

    [range, nil]
  end

  def commit?(ref, chdir: Dir.pwd)
    _, status = Open3.capture2e('git', 'rev-parse', '--verify', '--quiet', "#{ref}^{commit}", chdir:)
    status.success?
  end

  # git log prints the bytes a commit holds whatever their encoding, and Ruby tags them with the
  # locale's, which is US-ASCII under LC_ALL=C.
  def utf8(bytes) = bytes.dup.force_encoding(Encoding::UTF_8).scrub('?')

  def subject_problems(subject)
    reverted = REVERT.match(subject)
    return subject_problems(reverted[:subject]) if reverted
    return ['marks a fixup, amend, squash or WIP commit'] if UNFINISHED.match?(subject)
    return [] if SUBJECT.match?(subject)

    ["is not a Conventional Commit (\"type(scope): summary\" with a lowercase summary; types: #{TYPES.join(', ')})"]
  end

  def attribution_problems(text)
    line = text.each_line.find { attribution?(it) }
    line ? ["carries an AI attribution line: #{line.strip.inspect}"] : []
  end

  def attribution?(line)
    co_author = CO_AUTHOR.match(line)
    return BOT_ADDRESS.match?(co_author[:address].strip) if co_author

    TOOL_TRAILER.match?(line) || GENERATED_WITH.match?(line)
  end

  def lint(commits, title: nil, body: nil)
    lines = commits.filter_map do |commit|
      # git writes a merge commit's subject, but anyone can add trailers to its message.
      subject = commit.merge? ? [] : subject_problems(commit.subject).map { "subject #{it}" }
      problems = subject + attribution_problems(commit.message)
      "#{commit.sha} #{commit.subject.inspect}: #{problems.join('; ')}" unless problems.empty?
    end
    lines += subject_problems(title.strip).map { "pull request title #{title.strip.inspect} #{it}" } if title
    lines += attribution_problems(body).map { "pull request body #{it}" } if body
    lines
  end
end
