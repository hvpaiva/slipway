# frozen_string_literal: true

require 'test_helper'

class HelpRendererTest < Minitest::Test
  ROOT = <<~HELP
    Slipway keeps a registry of the development projects on your machine.

    Usage: slipway [OPTIONS] <COMMAND>

    Basic Commands:
      get         Display one or many resources
      create      Create a resource
      explain     Describe the fields of a resource type

    Settings Commands:
      config      Modify the configuration
      completion  Output shell completion code for the specified shell (bash, zsh, fish)
      man         Show the manual page of a command

    Other Commands:
      help        Help about any command
      version     Print the version of slipway

    Options:
          --color[=<WHEN>]  When to use color in the output; a bare --color means always [possible
                            values: auto, always, never]
      -n, --group <NAME>    The group scope for this request
          --config <PATH>   Path to the configuration file
      -h, --help            Print help (see more with '--help')
      -V, --version         Print the version and exit

    Use "slipway <COMMAND> --help" for more information about a given command.
  HELP

  GET = <<~HELP
    Display one or many resources

    Usage: slipway get [OPTIONS] <TYPE> [NAME]...

    Arguments:
      <TYPE>     [possible values: projects, groups]
      [NAME]...

    Options:
      -o, --output <FORMAT>  Output format [default: table] [possible values: table, wide, json, yaml,
                             name]
          --no-headers       When using the default output format, don't print headers
      -l, --selector <EXPR>  Selector (label query) to filter on
      -h, --help             Print help (see more with '--help')

    Use "slipway --help" for a list of global options (applies to all commands).
  HELP

  GET_PAGE = <<~HELP
    Display one or many resources.

    Usage: slipway get [OPTIONS] <TYPE> [NAME]...

    Arguments:
      <TYPE>
              [possible values: projects, groups]

      [NAME]...

    Options:
      -o, --output <FORMAT>
              Output format.

              [default: table]
              [possible values: table, wide, json, yaml, name]

          --no-headers
              When using the default output format, don't print headers.

      -l, --selector <EXPR>
              Selector (label query) to filter on.

      -h, --help
              Print help (see a summary with '-h').

    Examples:
      # List every project in the current group
      slipway get projects

      # List projects as JSON
      slipway get projects -o json

    Use "slipway --help" for a list of global options (applies to all commands).
  HELP

  CONFIG = <<~HELP
    Modify the configuration

    Usage: slipway config [OPTIONS] <COMMAND>

    Available Commands:
      view  Print the effective configuration
      path  Print the configuration file path

    Options:
      -h, --help  Print help (see more with '--help')

    Use "slipway config <COMMAND> --help" for more information about a given command.
    Use "slipway --help" for a list of global options (applies to all commands).
  HELP

  def setup
    @fixture = FixtureRegistry.new
    @plain = renderer(Slipway::CLI::Style.disabled)
  end

  def test_root_summary_puts_the_usage_under_the_description
    assert_equal ROOT, @plain.root(long: false)
  end

  def test_root_page_writes_each_option_as_a_block
    page = @plain.root

    assert_includes page, "Options:\n      --color[=<WHEN>]\n          When to use color in the output; a bare " \
                          "--color means always.\n\n          [possible values: auto, always, never]\n\n  " \
                          "-n, --group <NAME>\n          The group scope for this request.\n"
    assert_includes page, "  -h, --help\n          Print help (see a summary with '-h').\n"
  end

  def test_command_summary_lists_arguments_and_options_one_to_a_line
    assert_equal GET, @plain.command(*resolve('get'), long: false)
  end

  def test_command_page_puts_the_reference_sections_after_the_options
    assert_equal GET_PAGE, @plain.command(*resolve('get'))
  end

  def test_group_help_lists_subcommands_and_both_trailer_lines
    assert_equal CONFIG, @plain.command(*resolve('config'), long: false)
  end

  def test_long_only_options_are_padded_to_the_short_flag_column
    create = @plain.command(*resolve('create'), long: false)

    assert_includes create, "\n      --path <DIR>         Directory of the repository\n"
    assert_includes create, "\n  -h, --help               Print help (see more with '--help')\n"
  end

  def test_required_options_follow_the_options_placeholder
    own = Slipway::CLI::Command.new(name: 'x', summary: 'X', usage: '(A | B/C)')

    assert_includes @plain.command(*resolve('create')), "Usage: slipway create [OPTIONS] --path <DIR> <TYPE> <NAME>\n"
    assert_includes @plain.command(*resolve('config', 'view')), "Usage: slipway config view [OPTIONS]\n"
    assert_includes @plain.command(own, %w[x]), "Usage: slipway x [OPTIONS] (A | B/C)\n"
  end

  def test_labels_wider_than_the_label_column_put_their_text_on_the_next_line
    long = Slipway::CLI::Option.new(long: 'a-very-long-option-name', argument: 'WITH-A-LONG-ARGUMENT',
                                    description: 'Wrapped.')
    command = Slipway::CLI::Command.new(name: 'x', summary: 'X', options: [long, option('short', short: 's')])

    expected = "      --a-very-long-option-name <WITH-A-LONG-ARGUMENT>\n#{' ' * 34}Wrapped\n  " \
               "-s, --short#{' ' * 21}Short\n"

    assert_includes @plain.command(command, %w[x], long: false), expected
  end

  def test_text_wraps_at_the_width_under_its_own_column
    narrow = renderer(Slipway::CLI::Style.disabled, width: 40)
    words = 'one two three four five six seven eight nine ten.'
    command = Slipway::CLI::Command.new(name: 'x', summary: 'X', description: "#{words}\n  *  #{words}",
                                        options: [option('flag', short: 'f', description: words)])

    assert_includes narrow.command(command, %w[x], long: false),
                    "  -f, --flag  one two three four five\n              six seven eight nine ten\n"
    page = narrow.command(command, %w[x])

    assert_includes page, "one two three four five six seven eight\nnine ten.\n  " \
                          "*  one two three four five six seven\n     eight nine ten.\n"
    assert_includes page, "  -f, --flag\n          one two three four five six\n          seven eight nine ten.\n"
  end

  def test_width_never_exceeds_the_maximum
    wide = renderer(Slipway::CLI::Style.disabled, width: 300)
    command = Slipway::CLI::Command.new(name: 'x', summary: 'X', description: 'word ' * 40)

    assert_equal "#{(['word'] * 20).join(' ')}\n", wide.command(command, %w[x]).lines.first
  end

  def test_exit_statuses_glossaries_and_examples_follow_the_options_in_the_page_only
    words = Slipway::CLI::Glossary.new(title: 'Words', intro: 'The first that holds.',
                                       entries: { 'Clean' => 'Nothing to do.', 'Missing' => 'No directory.' })
    command = Slipway::CLI::Command.new(name: 'x', summary: 'X', description: 'Show.', glossaries: [words],
                                        exit_statuses: { '0' => 'Shown.', '130' => 'Interrupted.' },
                                        examples: [Slipway::CLI::Example.new(comment: 'Show', command: 'x')])

    assert_includes @plain.command(command, %w[x]),
                    "Print help (see a summary with '-h').\n\nWords:\n  The first that holds.\n\n  Clean    " \
                    "Nothing to do.\n  Missing  No directory.\n\nExit Status:\n  0    Shown.\n  130  Interrupted.\n\n" \
                    "Examples:\n  # Show\n  slipway x\n"
    refute_match(/Words:|Exit Status:|Examples:/, @plain.command(command, %w[x], long: false))
  end

  def test_root_glossaries_follow_the_options_in_the_page_only
    registry = Slipway::CLI::Registry.new(
      program: 'slipway', version: '0', description: 'D', globals: Slipway::CLI::Globals::ALL, commands: [],
      glossaries: [Slipway::CLI::Glossary.new(title: 'Environment Variables', entries: { 'X_HOME' => 'Home.' })]
    )
    root = Slipway::CLI::HelpRenderer.new(registry, Slipway::CLI::Style.disabled)

    assert_includes root.root, "Print the version and exit.\n\nEnvironment Variables:\n  X_HOME  Home.\n\nUse "
    refute_includes root.root(long: false), 'Environment Variables:'
  end

  def test_color_paints_headers_flags_and_examples_but_keeps_alignment_padding_outside
    colored = renderer(Slipway::CLI::Style.for('always', tty: false, env: {}))
    summary = colored.command(*resolve('get'), long: false)
    page = colored.command(*resolve('get'))

    assert_includes summary, "\e[1mOptions:\e[0m\n"
    assert_includes summary, "  \e[36m-o, --output <FORMAT>\e[0m  Output format"
    assert_includes summary, "      \e[36m--no-headers\e[0m       When using"
    assert_includes page, "  \e[90;3m# List projects as JSON\e[0m\n  \e[32mslipway\e[0m get projects \e[36m-o\e[0m"
    assert_equal GET, summary.gsub(/\e\[[\d;]*m/, '')
    assert_equal GET_PAGE, page.gsub(/\e\[[\d;]*m/, '')
  end

  def test_disabled_style_emits_no_escape_sequences
    refute_match(/\e\[/, @plain.root)
  end

  private

  def renderer(style, width: nil) = Slipway::CLI::HelpRenderer.new(@fixture.registry, style, width:)

  def resolve(*words) = @fixture.registry.resolve(words)

  def option(long, description: "#{long.capitalize}.", **attributes)
    Slipway::CLI::Option.new(long:, description:, **attributes)
  end
end
