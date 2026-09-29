# frozen_string_literal: true

require 'test_helper'
require_relative '../../rakelib/support/changelog'

# The committed pages under man/man1 have to be what the registry renders today. The date
# comes from CHANGELOG.md the way bin/generate-man reads it, so a release heading and a
# regenerated page move together.
class ManpageGoldenTest < Minitest::Test
  include GoldenHelper

  ROOT = File.expand_path('../..', __dir__)
  MAN_DIR = File.join(ROOT, 'man', 'man1')
  CHANGELOG = File.join(ROOT, 'CHANGELOG.md')
  REGENERATE = 'run bundle exec rake generate:man'

  # Empty until CHANGELOG.md has a release heading, the same rule bin/generate-man applies.
  def self.page_date = Changelog.release_date(File.read(CHANGELOG)).to_s

  REGISTRY = Slipway::Commands.registry(->(_context, _opts) { raise 'man pages do not build a runtime' })
  PAGES = Slipway::CLI::Manpage.new(REGISTRY, date: page_date, configuration: Slipway::Config::DOCUMENTATION).pages.freeze

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
