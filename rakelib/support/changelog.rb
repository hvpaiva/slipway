# frozen_string_literal: true

# Keep a Changelog layout: "## [Unreleased]" first, then release headings newest first, then
# the link references.
module Changelog
  UNRELEASED = '## [Unreleased]'
  UNRELEASED_LINE = /^## \[Unreleased\]\n/
  UNRELEASED_REFERENCE = /^\[Unreleased\]: \S+\n/
  # " [YANKED]" marks a release withdrawn from rubygems.org; it keeps its date.
  RELEASE_HEADING = /\A## \[(?<version>\d+\.\d+\.\d+)\] - (?<date>\d{4}-\d{2}-\d{2})(?<yanked> \[YANKED\])?\s*\z/
  LINK_REFERENCE = /\A\[(?<name>[^\]]+)\]: (?<url>\S+)\s*\z/

  # +date+ stays the ISO string as written, not a Date.
  Heading = Data.define(:version, :date, :yanked)

  module_function

  def headings(text)
    text.each_line.filter_map do |line|
      match = RELEASE_HEADING.match(line)
      Heading.new(version: match[:version], date: match[:date], yanked: !match[:yanked].nil?) if match
    end
  end

  def release_date(text)
    headings(text).first&.date
  end

  # nil when the heading is missing, "" when the section is empty; callers tell the two apart.
  def unreleased_entries(text)
    lines = text.lines
    start = lines.index { it.chomp == UNRELEASED }
    return unless start

    lines[(start + 1)..].take_while { !it.start_with?('## ') && !LINK_REFERENCE.match?(it) }.join.strip
  end

  def link_references(text)
    text.each_line.filter_map { LINK_REFERENCE.match(it) }.to_h { [it[:name], it[:url]] }
  end

  def cut(text, version, date, repo_url)
    raise ArgumentError, "CHANGELOG.md has no \"#{UNRELEASED}\" heading" unless unreleased_entries(text)

    released = text.sub(UNRELEASED_LINE) { "#{UNRELEASED}\n\n## [#{version}] - #{date}\n" }
    references = "[Unreleased]: #{repo_url}/compare/v#{version}...HEAD\n" \
                 "[#{version}]: #{repo_url}/releases/tag/v#{version}\n"
    return released.sub(UNRELEASED_REFERENCE) { references } if released.match?(UNRELEASED_REFERENCE)

    "#{released.chomp}\n\n#{references}"
  end

  def release_problems(text, version)
    references = link_references(text)
    [
      ("no \"## [#{version}] - YYYY-MM-DD\" heading" unless headings(text).any? { it.version == version }),
      ("no \"#{UNRELEASED}\" heading" unless unreleased_entries(text)),
      ("no [#{version}] link reference" unless references.key?(version)),
      ('no [Unreleased] link reference' unless references.key?('Unreleased'))
    ].compact
  end
end
