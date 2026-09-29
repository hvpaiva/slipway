# frozen_string_literal: true

require 'open3'

module Commits
  TYPES = %w[feat fix docs test refactor chore ci].freeze
  SUBJECT = /\A(#{TYPES.join('|')})(\([a-z0-9-]+\))?!?: [a-z]/
  UNFINISHED = /\A(fixup!|squash!|wip\b)/i
  ASSISTANTS = %w[claude anthropic copilot cursor codex chatgpt gpt- gemini assistant].freeze
  # Ruby's ^ already anchors at every line, and /m would let .* run past the end of a human
  # co-author's trailer into later lines, so the pattern is case-insensitive only.
  ATTRIBUTION_TRAILER = /^(Co-Authored-By|Generated-(by|with)|Assisted-by|Claude-Session):.*(#{ASSISTANTS.join('|')})/i
  GENERATED_WITH = /Generated with \[?Claude/i

  Commit = Data.define(:sha, :message) do
    def subject = message.lines.first.to_s.chomp
  end

  class Error < StandardError; end

  module_function

  # Merge commits are left out: git writes their message, not a contributor.
  def read(range, chdir: Dir.pwd)
    out, err, status = Open3.capture3('git', 'log', '--no-merges', '--no-show-signature', '--reverse', '-z',
                                      '--format=%h%x1f%B', range, '--', chdir:)
    raise Error, "git log #{range} failed: #{err.strip}" unless status.success?

    out.split("\0").map do |record|
      sha, message = record.split("\x1f", 2)
      Commit.new(sha:, message: message.to_s)
    end
  end

  def subject_problems(subject)
    return ['marks a fixup, squash or WIP commit'] if UNFINISHED.match?(subject)
    return [] if SUBJECT.match?(subject)

    ["is not a Conventional Commit (\"type(scope): summary\" with a lowercase summary; types: #{TYPES.join(', ')})"]
  end

  def attribution_problems(text)
    line = text.each_line.find { ATTRIBUTION_TRAILER.match?(it) || GENERATED_WITH.match?(it) }
    line ? ["carries an AI attribution line: #{line.strip.inspect}"] : []
  end

  def lint(commits, title: nil, body: nil)
    lines = commits.filter_map do |commit|
      problems = subject_problems(commit.subject).map { "subject #{it}" } + attribution_problems(commit.message)
      "#{commit.sha} #{commit.subject.inspect}: #{problems.join('; ')}" unless problems.empty?
    end
    lines += subject_problems(title.strip).map { "pull request title #{title.strip.inspect} #{it}" } if title
    lines += attribution_problems(body).map { "pull request body #{it}" } if body
    lines
  end
end
