# frozen_string_literal: true

require 'test_helper'

class ManpageTest < Minitest::Test
  include ShellHarness

  FIXTURES = File.expand_path('../../fixtures/man', __dir__)
  DATE = '2026-09-29'

  def setup
    @registry = FixtureRegistry.new.registry
    @manpage = Slipway::CLI::Manpage.new(@registry, date: DATE)
  end

  def test_pages_cover_the_root_and_every_visible_command_and_group
    assert_equal %w[slipway.1 slipway-get.1 slipway-create.1 slipway-config.1 slipway-config-view.1
                    slipway-config-path.1 slipway-help.1 slipway-version.1 slipway-completion.1 slipway-man.1],
                 @manpage.pages.keys
  end

  def test_root_page_matches_the_golden_file
    assert_equal File.read(File.join(FIXTURES, 'slipway.1')), @manpage.page([])
    assert_equal @manpage.page([]), @manpage.pages['slipway.1']
  end

  def test_command_page_matches_the_golden_file
    assert_equal File.read(File.join(FIXTURES, 'slipway-get.1')), @manpage.page(%w[get])
  end

  def test_title_line_carries_the_date_and_source_given
    page = Slipway::CLI::Manpage.new(@registry, date: '2030-01-02', source: 'Slipway 9').page(%w[config view])

    assert_equal '.TH "SLIPWAY-CONFIG-VIEW" "1" "2030-01-02" "Slipway 9" "Slipway Manual"', page.lines[1].chomp
    assert_equal '.TH "SLIPWAY-GET" "1" "2026-09-29" "slipway 0.1.0" "Slipway Manual"',
                 @manpage.page(%w[get]).lines[1].chomp
  end

  def test_group_page_lists_subcommands_and_nested_page_points_back_at_its_group
    group = @manpage.page(%w[config])
    nested = @manpage.page(%w[config view])

    assert_includes group, ".SH COMMANDS\n.TP 6\n\\fBview\\fR\nPrint the effective configuration\n"
    refute_includes group, '.SS'
    assert_includes group, ".SH SYNOPSIS\n.SY \"slipway config\"\n.I COMMAND\n.RI [ flags ]\n.YS\n"
    assert_equal ".SH \"SEE ALSO\"\n.BR slipway (1),\n.BR slipway\\-config (1)\n", nested[/\.SH "SEE ALSO".*/m]
  end

  def test_option_notes_and_escaping
    page = @manpage.page(%w[create])

    assert_includes page, "\\fB\\-\\-path\\fR \\fIDIR\\fR\nDirectory of the repository. (required)\n"
    assert_includes page, "\\fB\\-\\-dry\\-run\\fR \\fIMODE\\fR\nOnly print the object that would be sent. " \
                          "One of: none, client. (default \"none\")\n"
    assert_includes page, ".SH SYNOPSIS\n.SY \"slipway create\"\n.B \\-\\-path\n.I DIR\n.I TYPE\\&\n.I NAME\\&\n" \
                          ".RI [ flags ]\n.YS\n"
    assert_includes page, '\fB\-\-label\fR \fIKEY=VALUE\fR'
  end

  def test_environment_and_configuration_are_injectable
    manpage = Slipway::CLI::Manpage.new(@registry, date: DATE, environment: { 'X_Y' => 'Means "x" - or y.' },
                                                   configuration: { 'key' => "First.\n\nSecond paragraph." })
    page = manpage.page([])

    assert_includes page, ".SH ENVIRONMENT\n.TP\n\\fBX_Y\\fR\nMeans \"x\" \\- or y.\n.SH FILES\n"
    assert_includes page, ".SH CONFIGURATION\n.TP\n\\fBkey\\fR\nFirst.\n.PP\nSecond paragraph.\n.SH \"EXIT STATUS\"\n"
    refute_includes page, 'SLIPWAY_THEME'
    refute_includes page, 'theme'
  end

  def test_paragraphs_turn_bullet_lines_into_indented_items_and_drop_leading_spaces
    text = "Intro.\n\n  *  First item.\n  *  Second item.\n\n Indented prose."

    assert_equal ['Intro.', '.IP \(bu 2', 'First item.', '.IP \(bu 2', 'Second item.', '.PP', 'Indented prose.'],
                 Slipway::CLI::Roff.paragraphs(text)
  end

  def test_roff_text_escapes_control_characters
    roff = Slipway::CLI::Roff

    assert_equal '\-\-no\-headers', roff.text('--no-headers')
    assert_equal 'C:\eUsers', roff.text('C:\Users')
    assert_equal '\&.hidden', roff.text('.hidden')
    assert_equal "\\&'quoted", roff.text("'quoted")
    assert_equal '"a \(dq b"', roff.argument('a " b')
    assert_equal 'plain', roff.argument('plain')
  end

  def test_page_for_an_unknown_path_is_a_usage_error
    assert_raises(Slipway::CLI::UsageError) { @manpage.page(%w[bogus]) }
  end

  def test_every_page_renders_without_groff_warnings
    skip 'groff is not installed' unless shell_installed?('groff')

    Dir.mktmpdir('slipway-man-') do |dir|
      @manpage.pages.each do |name, roff|
        file = File.join(dir, name)
        File.write(file, roff)
        out, err, status = Open3.capture3('groff', '-man', '-Tutf8', '-ww', file)

        assert_predicate status, :success?, name
        assert_empty err, name
        assert_includes out, name.delete_suffix('.1').upcase
      end
    end
  end
end
