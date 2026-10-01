# frozen_string_literal: true

require 'test_helper'

class HelpRendererTest < Minitest::Test
  ROOT = <<~HELP
    Slipway keeps a registry of the development projects on your machine.

    Basic Commands:
      get             Display one or many resources
      create          Create a resource
      explain         Describe the fields of a resource type

    Settings Commands:
      config          Modify the configuration
      completion      Output shell completion code for the specified shell (bash, zsh, fish)
      man             Show the manual page of a command

    Other Commands:
      help            Help about any command
      version         Print the version of slipway

    Options:
          --color[=WHEN]   When to use color in the output; a bare --color means always. One of: auto, always, never.
      -n, --group NAME     The group scope for this request.
          --config PATH    Path to the configuration file.
      -h, --help           Print help and exit.
      -V, --version        Print the version and exit.

    Usage:
      slipway [flags] COMMAND [ARGS...]

    Use "slipway <command> --help" for more information about a given command.
  HELP

  GET = <<~HELP
    Display one or many resources.

    Examples:
      # List every project in the current group
      slipway get projects

      # List projects as JSON
      slipway get projects -o json

    Options:
      -o, --output FORMAT   Output format. One of: table, wide, json, yaml, name. (default "table")
          --no-headers      When using the default output format, don't print headers.
      -l, --selector EXPR   Selector (label query) to filter on.

    Usage:
      slipway get TYPE [NAME...] [flags]

    Use "slipway --help" for a list of global options (applies to all commands).
  HELP

  CONFIG = <<~HELP
    Modify the configuration

    Available Commands:
      view            Print the effective configuration
      path            Print the configuration file path

    Usage:
      slipway config COMMAND [flags]

    Use "slipway config <command> --help" for more information about a given command.
    Use "slipway --help" for a list of global options (applies to all commands).
  HELP

  CREATE_OPTIONS = <<~HELP
    Options:
          --path DIR          Directory of the repository. (required)
          --from-dir DIR      Directory to scan.
          --label KEY=VALUE   Label to set.
          --output FORMAT     Output format. One of: table, yaml, json. (default "table")
  HELP

  def setup
    @fixture = FixtureRegistry.new
    @plain = renderer(Slipway::CLI::Style.disabled)
  end

  def test_root_help_lists_sections_in_kubectl_order
    assert_equal ROOT, @plain.root
  end

  def test_command_help_puts_examples_before_options_and_usage_last
    assert_equal GET, @plain.command(*@fixture.registry.resolve(%w[get]))
  end

  def test_group_help_lists_subcommands_and_both_trailer_lines
    assert_equal CONFIG, @plain.command(*@fixture.registry.resolve(%w[config]))
  end

  def test_long_only_options_are_padded_to_the_short_flag_column
    assert_includes @plain.command(*@fixture.registry.resolve(%w[create])), CREATE_OPTIONS
  end

  def test_required_options_lead_the_usage_line_and_flags_always_close_it
    create = @plain.command(*@fixture.registry.resolve(%w[create]))
    view = @plain.command(*@fixture.registry.resolve(%w[config view]))
    own = Slipway::CLI::Command.new(name: 'x', summary: 'X', usage: '(A | B/C)')

    assert_includes create, "Usage:\n  slipway create --path DIR TYPE NAME [flags]\n"
    assert_includes view, "Usage:\n  slipway config view [flags]\n"
    assert_includes @plain.command(own, %w[x]), "Usage:\n  slipway x (A | B/C) [flags]\n"
  end

  def test_labels_wider_than_the_flag_column_wrap_their_description
    long = Slipway::CLI::Option.new(long: 'a-very-long-option-name', argument: 'WITH-A-LONG-ARGUMENT',
                                    description: 'Wrapped.')
    command = Slipway::CLI::Command.new(name: 'x', summary: 'X', options: [long, option('short', short: 's')])

    expected = "  #{' ' * 4}--a-very-long-option-name WITH-A-LONG-ARGUMENT\n  #{' ' * 30}   Wrapped.\n  " \
               "-s, --short#{' ' * 19}   Short.\n"

    assert_includes @plain.command(command, %w[x]), expected
  end

  def test_exit_statuses_follow_the_description_aligned_on_the_widest_status
    command = Slipway::CLI::Command.new(name: 'x', summary: 'X', description: 'Compare.',
                                        exit_statuses: { '0' => 'Nothing differs.', '130' => 'Interrupted.' },
                                        examples: [Slipway::CLI::Example.new(comment: 'Compare', command: 'x')])

    assert_includes @plain.command(command, %w[x]),
                    "Compare.\n\nExit Status:\n  0     Nothing differs.\n  130   Interrupted.\n\nExamples:\n"
    refute_includes @plain.command(*@fixture.registry.resolve(%w[get])), 'Exit Status:'
  end

  def test_glossaries_follow_the_description_with_their_intro_and_aligned_terms
    words = Slipway::CLI::Glossary.new(title: 'Words', intro: 'The first that holds.',
                                       entries: { 'Clean' => 'Nothing to do.', 'Missing' => 'No directory.' })
    plain = Slipway::CLI::Glossary.new(title: 'Columns', entries: { 'NAME' => 'The name.' })
    command = Slipway::CLI::Command.new(name: 'x', summary: 'X', description: 'Show.', glossaries: [words, plain],
                                        exit_statuses: { '0' => 'Shown.' })

    assert_includes @plain.command(command, %w[x]),
                    "Show.\n\nWords:\n  The first that holds.\n\n  Clean     Nothing to do.\n  " \
                    "Missing   No directory.\n\nColumns:\n  NAME   The name.\n\nExit Status:\n"
  end

  def test_color_paints_headers_flags_and_examples_but_keeps_alignment_padding_outside
    colored = renderer(Slipway::CLI::Style.for('always', tty: false, env: {}))
              .command(*@fixture.registry.resolve(%w[get]))

    assert_includes colored, "\e[1mOptions:\e[0m\n"
    assert_includes colored, "  \e[36m-o, --output FORMAT\e[0m   Output format."
    assert_includes colored, "      \e[36m--no-headers\e[0m      When using"
    assert_includes colored, "  \e[90;3m# List projects as JSON\e[0m\n  \e[32mslipway\e[0m get projects \e[36m-o\e[0m"
    assert_equal GET, colored.gsub(/\e\[[\d;]*m/, '')
  end

  def test_disabled_style_emits_no_escape_sequences
    refute_match(/\e\[/, @plain.root)
  end

  private

  def renderer(style) = Slipway::CLI::HelpRenderer.new(@fixture.registry, style)

  def option(long, **attributes) = Slipway::CLI::Option.new(long:, description: "#{long.capitalize}.", **attributes)
end
