# frozen_string_literal: true

# Reads and rewrites CHANGELOG.md in the Keep a Changelog layout this project follows: an
# "## [Unreleased]" section first, then "## [X.Y.Z] - YYYY-MM-DD" headings newest first,
# then the link references.
module Changelog
  UNRELEASED = '## [Unreleased]'
  UNRELEASED_LINE = /^## \[Unreleased\]\n/
  UNRELEASED_REFERENCE = /^\[Unreleased\]: \S+\n/
  # A released version; " [YANKED]" marks one withdrawn from rubygems.org, which keeps its date.
  RELEASE_HEADING = /\A## \[(?<version>\d+\.\d+\.\d+)\] - (?<date>\d{4}-\d{2}-\d{2})(?<yanked> \[YANKED\])?\s*\z/
  LINK_REFERENCE = /\A\[(?<name>[^\]]+)\]: (?<url>\S+)\s*\z/

  # One release heading: +date+ is the ISO date string as written.
  Heading = Data.define(:version, :date, :yanked)

  module_function

  # Every release heading in file order, which is newest first.
  def headings(text)
    text.each_line.filter_map do |line|
      match = RELEASE_HEADING.match(line)
      Heading.new(version: match[:version], date: match[:date], yanked: !match[:yanked].nil?) if match
    end
  end

  # The date of the newest release heading, or nil while nothing has been released. The man
  # pages carry this date, so bin/generate-man and the golden manpage test both call it.
  def release_date(text)
    headings(text).first&.date
  end

  # The text under "## [Unreleased]" up to the next heading or the link references, stripped;
  # nil when the file has no such heading.
  def unreleased_entries(text)
    lines = text.lines
    start = lines.index { it.chomp == UNRELEASED }
    return unless start

    lines[(start + 1)..].take_while { !it.start_with?('## ') && !LINK_REFERENCE.match?(it) }.join.strip
  end

  # The link references at the end of the file, name => URL, in file order.
  def link_references(text)
    text.each_line.filter_map { LINK_REFERENCE.match(it) }.to_h { [it[:name], it[:url]] }
  end

  # The file after releasing +version+ on +date+: the unreleased entries move under a dated
  # heading below an empty "## [Unreleased]", [Unreleased] compares from the new tag, and the
  # new version links to its release page. Older references stay as they are.
  def cut(text, version, date, repo_url)
    raise ArgumentError, "CHANGELOG.md has no \"#{UNRELEASED}\" heading" unless unreleased_entries(text)

    released = text.sub(UNRELEASED_LINE) { "#{UNRELEASED}\n\n## [#{version}] - #{date}\n" }
    references = "[Unreleased]: #{repo_url}/compare/v#{version}...HEAD\n" \
                 "[#{version}]: #{repo_url}/releases/tag/v#{version}\n"
    return released.sub(UNRELEASED_REFERENCE) { references } if released.match?(UNRELEASED_REFERENCE)

    "#{released.chomp}\n\n#{references}"
  end

  # What keeps +text+ from being the changelog of the released +version+; empty when it is.
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
