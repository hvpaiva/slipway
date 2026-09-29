# frozen_string_literal: true

require 'test_helper'

# The committed pages under man/man1 have to be what the registry renders today. The date
# comes from CHANGELOG.md the way bin/generate-man reads it, so a release heading and a
# regenerated page move together.
class ManpageGoldenTest < Minitest::Test
  include GoldenHelper

  ROOT = File.expand_path('../..', __dir__)
  MAN_DIR = File.join(ROOT, 'man', 'man1')
  CHANGELOG = File.join(ROOT, 'CHANGELOG.md')
  RELEASE_HEADING = /\A## \[\d+\.\d+\.\d+\] - (\d{4}-\d{2}-\d{2})\s*\z/
  FALLBACK_DATE = '2026-09-29'
  REGENERATE = 'run bundle exec rake generate:man'

  def self.page_date
    return FALLBACK_DATE unless File.exist?(CHANGELOG)

    File.foreach(CHANGELOG) do |line|
      match = RELEASE_HEADING.match(line)
      return match[1] if match
    end
    FALLBACK_DATE
  end

  REGISTRY = Slipway::Commands.registry(->(_context, _opts) { raise 'man pages do not build a runtime' })
  PAGES = Slipway::CLI::Manpage.new(REGISTRY, date: page_date).pages.freeze

  PAGES.each do |name, roff|
    define_method("test_#{name.tr('.-', '__')}_is_fresh") do
      assert_text_file(File.join(MAN_DIR, name), roff, regenerate: REGENERATE)
    end
  end

  def test_man1_holds_exactly_the_rendered_pages
    assert_equal PAGES.keys.sort, Dir.children(MAN_DIR).sort
  end

  def test_pages_carry_the_changelog_date
    assert_includes PAGES.fetch('slipway.1'), %(.TH "SLIPWAY" "1" "#{self.class.page_date}" "slipway #{Slipway::VERSION}")
  end
end
