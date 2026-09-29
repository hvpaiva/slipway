# frozen_string_literal: true

require 'date'
require 'test_helper'

# The man pages take their date from CHANGELOG.md and the release notes are cut from it, so
# its shape is checked on every run rather than on release day.
class ChangelogTest < Minitest::Test
  PATH = File.expand_path('../../CHANGELOG.md', __dir__)
  REPOSITORY = 'https://github.com/hvpaiva/slipway'
  INTRODUCTION = <<~MARKDOWN
    # Changelog

    All notable changes to this project will be documented in this file.

    The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
    and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

  MARKDOWN
  UNRELEASED = 'Unreleased'
  UNRELEASED_HEADING = '## [Unreleased]'
  HEADING = /\A## \[(?<label>[^\]]+)\](?<rest>.*)\z/
  RELEASE = /\A - (?<date>\d{4}-\d{2}-\d{2})(?: \[YANKED\])?\z/
  VERSION = /\A\d+\.\d+\.\d+\z/
  REFERENCE = /\A\[(?<label>[^\]]+)\]: (?<url>\S+)\z/

  RELEASED = <<~MARKDOWN.freeze
    #{INTRODUCTION}## [Unreleased]

    ## [1.1.0] - 2026-11-02

    ### Fixed

    - Something.

    ## [1.0.1] - 2026-11-02 [YANKED]

    ### Fixed

    - Something else.

    ## [1.0.0] - 2026-10-01

    ### Added

    - Everything.

    [Unreleased]: #{REPOSITORY}/compare/v1.1.0...HEAD
    [1.1.0]: #{REPOSITORY}/releases/tag/v1.1.0
    [1.0.1]: #{REPOSITORY}/releases/tag/v1.0.1
    [1.0.0]: #{REPOSITORY}/releases/tag/v1.0.0
  MARKDOWN

  def test_the_changelog_keeps_the_format
    assert_empty problems(File.read(PATH), version: Slipway::VERSION)
  end

  def test_a_released_changelog_keeps_the_format
    assert_empty problems(RELEASED, version: '1.1.0')
  end

  def test_an_unreleased_changelog_links_to_the_commits_of_main
    text = "#{INTRODUCTION}## [Unreleased]\n\n### Added\n\n- Everything.\n\n[Unreleased]: #{REPOSITORY}/commits/main\n"

    assert_empty problems(text, version: '0.1.0')
    assert_equal ["[Unreleased] links to #{REPOSITORY}/compare/v0.1.0...HEAD, expected #{REPOSITORY}/commits/main"],
                 problems(text.sub('commits/main', 'compare/v0.1.0...HEAD'), version: '0.1.0')
  end

  def test_a_broken_changelog_reports_every_problem
    broken = RELEASED.sub('## [Unreleased]', "## [Unreleased]\n\n## [Unreleased]")
                     .sub('2026-10-01', '2026-13-01').sub('[1.1.0] - 2026-11-02', '[1.1.0] - 2026-10-02')
                     .sub("[1.0.1]: #{REPOSITORY}/releases/tag/v1.0.1\n", '')

    assert_equal ['2 [Unreleased] headings, expected exactly one',
                  '## [1.0.1] - 2026-11-02 [YANKED] is newer than the release above it',
                  '## [1.0.0] - 2026-13-01 has an invalid date',
                  '[1.0.1] has no link reference',
                  'the newest release is 1.1.0, but Slipway::VERSION is 2.0.0'],
                 problems(broken, version: '2.0.0')
  end

  def test_the_first_section_is_unreleased_and_headings_are_releases
    text = RELEASED.sub("## [Unreleased]\n\n", '').sub('## [1.0.0] - 2026-10-01', '## 1.0.0 (2026-10-01)')

    assert_equal ['the first section is ## [1.1.0] - 2026-11-02, expected ## [Unreleased]',
                  'no [Unreleased] heading',
                  '## 1.0.0 (2026-10-01) is not ## [x.y.z] - YYYY-MM-DD'],
                 problems(text, version: '1.1.0').first(3)
  end

  def test_the_introduction_and_the_trailing_references_are_required
    text = RELEASED.sub('# Changelog', '# Changes').sub("[1.0.0]: #{REPOSITORY}/releases/tag/v1.0.0\n",
                                                        "\n[1.0.0]: #{REPOSITORY}/releases/tag/v1.0.0\nThe end.\n")

    assert_equal ['the introduction differs from Keep a Changelog 1.1.0',
                  'the link references are not the last lines of the file'],
                 problems(text, version: '1.1.0')
  end

  private

  def problems(text, version:)
    lines = text.lines(chomp: true)
    headings = lines.grep(/\A## /)
    [*introduction_problems(text), *section_problems(headings), *date_problems(headings),
     *reference_problems(lines, headings), *version_problems(headings, version)]
  end

  def introduction_problems(text)
    text.start_with?(INTRODUCTION) ? [] : ['the introduction differs from Keep a Changelog 1.1.0']
  end

  def section_problems(headings)
    first = headings.first
    count = headings.count(UNRELEASED_HEADING)
    found = []
    found << "the first section is #{first}, expected #{UNRELEASED_HEADING}" if first != UNRELEASED_HEADING
    found << "no [#{UNRELEASED}] heading" if count.zero?
    found << "#{count} [#{UNRELEASED}] headings, expected exactly one" if count > 1
    found + release_headings(headings).reject { release(it) }.map { "#{it} is not ## [x.y.z] - YYYY-MM-DD" }
  end

  def date_problems(headings)
    parsed = dates(headings)
    order = parsed.select(&:last).each_cons(2).filter_map do |(_, newer), (heading, older)|
      "#{heading} is newer than the release above it" if older > newer
    end
    order + parsed.reject(&:last).map { "#{it.first} has an invalid date" }
  end

  def dates(headings)
    release_headings(headings).filter_map do |heading|
      match = release(heading)
      [heading, parse_date(match[:date])] if match
    end
  end

  def reference_problems(lines, headings)
    references = lines.filter_map { REFERENCE.match(it) }
    trailing = lines.reverse.drop_while(&:empty?).take_while { REFERENCE.match?(it) }
    urls = references.to_h { [it[:label], it[:url]] }
    labels = headings.filter_map { HEADING.match(it)&.[](:label) }.uniq
    found = []
    found << 'the link references are not the last lines of the file' unless trailing.size == references.size
    found + labels.reject { urls.key?(it) }.map { "[#{it}] has no link reference" } + link_problems(urls, labels)
  end

  def link_problems(urls, labels)
    releases = labels.grep(VERSION)
    unreleased = releases.empty? ? "#{REPOSITORY}/commits/main" : "#{REPOSITORY}/compare/v#{releases.first}...HEAD"
    expected = { UNRELEASED => unreleased, **releases.to_h { [it, "#{REPOSITORY}/releases/tag/v#{it}"] } }
    expected.filter_map do |label, url|
      "[#{label}] links to #{urls[label]}, expected #{url}" if urls.key?(label) && urls[label] != url
    end
  end

  def version_problems(headings, version)
    newest = release_headings(headings).find { release(it) }
    label = newest && HEADING.match(newest)[:label]
    return [] if label.nil? || label == version

    ["the newest release is #{label}, but Slipway::VERSION is #{version}"]
  end

  def release_headings(headings) = headings.reject { it == UNRELEASED_HEADING }

  def release(heading)
    match = HEADING.match(heading)
    match && VERSION.match?(match[:label]) ? RELEASE.match(match[:rest]) : nil
  end

  def parse_date(value)
    Date.iso8601(value)
  rescue Date::Error
    nil
  end
end
