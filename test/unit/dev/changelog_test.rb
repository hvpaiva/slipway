# frozen_string_literal: true

require 'test_helper'
require_relative '../../../rakelib/support/changelog'

class ChangelogParserTest < Minitest::Test
  REPO = 'https://github.com/hvpaiva/slipway'
  ROOT = File.expand_path('../../..', __dir__)

  UNRELEASED_ONLY = <<~MARKDOWN
    # Changelog

    All notable changes to this project will be documented in this file.

    ## [Unreleased]

    ### Added

    - `get` and `describe`.
    - Shell completion.

    [Unreleased]: https://github.com/hvpaiva/slipway/commits/main
  MARKDOWN

  CUT = <<~MARKDOWN
    # Changelog

    All notable changes to this project will be documented in this file.

    ## [Unreleased]

    ## [0.1.0] - 2026-10-01

    ### Added

    - `get` and `describe`.
    - Shell completion.

    [Unreleased]: https://github.com/hvpaiva/slipway/compare/v0.1.0...HEAD
    [0.1.0]: https://github.com/hvpaiva/slipway/releases/tag/v0.1.0
  MARKDOWN

  RELEASED = <<~MARKDOWN
    # Changelog

    ## [Unreleased]

    ### Fixed

    - `apply` reports unchanged files.

    ## [0.2.0] - 2026-11-02 [YANKED]

    ### Added

    - `label --overwrite`.

    ## [0.1.0] - 2026-10-01

    ### Added

    - `get` and `describe`.

    [Unreleased]: https://github.com/hvpaiva/slipway/compare/v0.2.0...HEAD
    [0.2.0]: https://github.com/hvpaiva/slipway/releases/tag/v0.2.0
    [0.1.0]: https://github.com/hvpaiva/slipway/releases/tag/v0.1.0
  MARKDOWN

  RELEASED_AGAIN_REFERENCES = <<~MARKDOWN
    [Unreleased]: https://github.com/hvpaiva/slipway/compare/v0.3.0...HEAD
    [0.3.0]: https://github.com/hvpaiva/slipway/releases/tag/v0.3.0
    [0.2.0]: https://github.com/hvpaiva/slipway/releases/tag/v0.2.0
    [0.1.0]: https://github.com/hvpaiva/slipway/releases/tag/v0.1.0
  MARKDOWN

  def test_an_unreleased_only_file_has_no_release_date
    assert_nil Changelog.release_date(UNRELEASED_ONLY)
    assert_empty Changelog.headings(UNRELEASED_ONLY)
  end

  def test_unreleased_entries_stop_at_the_link_references
    assert_equal "### Added\n\n- `get` and `describe`.\n- Shell completion.",
                 Changelog.unreleased_entries(UNRELEASED_ONLY)
  end

  def test_unreleased_entries_stop_at_the_next_release
    assert_equal "### Fixed\n\n- `apply` reports unchanged files.", Changelog.unreleased_entries(RELEASED)
  end

  def test_unreleased_entries_are_empty_right_after_a_cut_and_nil_without_the_heading
    assert_equal '', Changelog.unreleased_entries(CUT)
    assert_nil Changelog.unreleased_entries("# Changelog\n\n## [0.1.0] - 2026-10-01\n")
  end

  def test_cut_moves_the_entries_under_a_dated_heading_and_rewrites_the_references
    assert_equal CUT, Changelog.cut(UNRELEASED_ONLY, '0.1.0', '2026-10-01', REPO)
  end

  def test_cut_keeps_older_references_below_the_new_one
    cut = Changelog.cut(RELEASED, '0.3.0', '2026-12-03', REPO)

    assert_includes cut, "## [Unreleased]\n\n## [0.3.0] - 2026-12-03\n\n### Fixed\n"
    assert cut.end_with?(RELEASED_AGAIN_REFERENCES)
    assert_equal %w[0.3.0 0.2.0 0.1.0], Changelog.headings(cut).map(&:version)
  end

  def test_cut_appends_the_references_when_the_file_has_none
    cut = Changelog.cut("# Changelog\n\n## [Unreleased]\n\n- One.\n", '0.1.0', '2026-10-01', REPO)

    references = "[Unreleased]: #{REPO}/compare/v0.1.0...HEAD\n[0.1.0]: #{REPO}/releases/tag/v0.1.0\n"

    assert cut.end_with?("- One.\n\n#{references}")
  end

  def test_cut_refuses_a_file_without_an_unreleased_heading
    error = assert_raises(ArgumentError) { Changelog.cut("# Changelog\n", '0.1.0', '2026-10-01', REPO) }

    assert_equal 'CHANGELOG.md has no "## [Unreleased]" heading', error.message
  end

  def test_release_date_is_the_newest_heading_and_accepts_a_yanked_one
    assert_equal '2026-11-02', Changelog.release_date(RELEASED)
    assert_equal [true, false], Changelog.headings(RELEASED).map(&:yanked)
    assert_equal '2026-10-01', Changelog.release_date(CUT)
  end

  def test_link_references_map_names_to_urls
    assert_equal({ 'Unreleased' => "#{REPO}/commits/main" }, Changelog.link_references(UNRELEASED_ONLY))
    assert_equal %w[Unreleased 0.2.0 0.1.0], Changelog.link_references(RELEASED).keys
  end

  def test_release_problems_are_empty_for_a_released_version
    assert_empty Changelog.release_problems(CUT, '0.1.0')
    assert_empty Changelog.release_problems(RELEASED, '0.2.0')
  end

  def test_release_problems_name_each_missing_part
    assert_equal ['no "## [0.1.0] - YYYY-MM-DD" heading', 'no [0.1.0] link reference'],
                 Changelog.release_problems(UNRELEASED_ONLY, '0.1.0')
    assert_equal ['no "## [0.1.0] - YYYY-MM-DD" heading', 'no "## [Unreleased]" heading',
                  'no [0.1.0] link reference', 'no [Unreleased] link reference'],
                 Changelog.release_problems("# Changelog\n", '0.1.0')
  end

  def test_the_project_changelog_can_be_cut
    text = File.read(File.join(ROOT, 'CHANGELOG.md'))
    entries = Changelog.unreleased_entries(text)
    cut = Changelog.cut(text, '9.9.9', '2030-01-01', REPO)

    refute_nil entries
    assert_equal '', Changelog.unreleased_entries(cut)
    assert_equal '2030-01-01', Changelog.release_date(cut)
    assert_includes cut, "## [9.9.9] - 2030-01-01\n\n#{entries}"
    assert_empty Changelog.release_problems(cut, '9.9.9')
  end
end
