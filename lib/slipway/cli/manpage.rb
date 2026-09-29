# frozen_string_literal: true

module Slipway
  module CLI
    # Escapes text for roff and spells the few man(7) macros the pages use.
    module Roff
      BULLET = /\A\s*\*\s+/

      module_function

      # Backslashes become \e and hyphens \- so options stay searchable; a line that would
      # start with a control character is neutralized with \&.
      def text(value)
        value.to_s.gsub('\\', '\e').gsub('-', '\-').sub(/\A(?=[.'])/) { '\&' }
      end

      # A macro argument, quoted only when it holds a space; double quotes become \(dq.
      def argument(value)
        escaped = text(value).gsub('"', '\(dq')
        escaped.include?(' ') ? %("#{escaped}") : escaped
      end

      # A section heading: `.SH TITLE`.
      def heading(title) = ".SH #{argument(title)}"

      # A subsection heading: `.SS TITLE`.
      def subheading(title) = ".SS #{argument(title)}"

      # +value+ in bold, escaped.
      def bold(value) = "\\fB#{text(value)}\\fR"

      # +value+ in italics, escaped.
      def italic(value) = "\\fI#{text(value)}\\fR"

      # Paragraphs separated by blank lines become .PP breaks; the first follows the
      # heading directly, since a paragraph macro right after .SH is a lint error. A line
      # starting with `*` is a bullet item with a hanging indent, and leading spaces, which
      # the terminal help keeps, are dropped because roff would break the line on them.
      def paragraphs(value)
        value.to_s.split(/\n{2,}/).flat_map.with_index do |paragraph, index|
          lines = paragraph.lines(chomp: true).flat_map { line(it) }
          index.zero? || lines.first.start_with?('.IP') ? lines : ['.PP', *lines]
        end
      end

      # One line of a paragraph: a bullet item as `.IP` plus its text, or the escaped text.
      def line(value)
        return [text(value.lstrip)] unless BULLET.match?(value)

        ['.IP \(bu 2', text(value.sub(BULLET, ''))]
      end

      # A .TP entry; +indent+ (in ens) aligns a list of short labels in one column.
      def tagged(label, description, indent: nil) = [indent ? ".TP #{indent}" : '.TP', label, *paragraphs(description)]

      # A cross reference for SEE ALSO: `.BR name (1)`.
      def reference(name) = ".BR #{text(name)} (1)"
    end

    # Renders one man(1) page per visible command and group, plus the root page, from
    # the registry. The date is passed in so the output is reproducible.
    class Manpage
      SECTION = '1'
      MANUAL = 'Slipway Manual'
      EXIT_STATUSES = {
        '0' => 'Success.',
        '1' => 'Runtime error, such as a missing resource or an unreadable manifest.',
        '2' => 'Usage error: unknown command, unknown flag or invalid argument.',
        '130' => 'Interrupted by SIGINT.'
      }.freeze
      DEFAULT_ENVIRONMENT = {
        'SLIPWAY_CONFIG' => 'Path of the configuration file; overridden by --config.',
        'SLIPWAY_DATA_HOME' => 'Directory holding the registry: group and project manifests.',
        'SLIPWAY_COLOR' => 'When to use color (auto, always or never); overridden by --color.',
        'SLIPWAY_THEME' => 'Color theme (dark or light).',
        'SLIPWAY_EDITOR' => 'Editor used by edit; takes precedence over VISUAL and EDITOR.',
        'SLIPWAY_GROUP' => 'Default group scope; overridden by --group.',
        'SLIPWAY_DEBUG' => 'When non-empty, unexpected errors also print their class and backtrace.',
        'NO_COLOR' => 'When non-empty, disables color in auto mode.',
        'FORCE_COLOR' => 'When non-empty, enables color in auto mode even without a terminal.',
        'CLICOLOR_FORCE' => 'Same as FORCE_COLOR.',
        'VISUAL' => 'Editor used by edit when SLIPWAY_EDITOR and the editor configuration key are unset.',
        'EDITOR' => 'Editor used by edit when VISUAL is unset as well.',
        'XDG_CONFIG_HOME' => 'Base of the configuration directory (default ~/.config).',
        'XDG_DATA_HOME' => 'Base of the data directory (default ~/.local/share).'
      }.freeze

      # +source+ fills the fourth .TH field and defaults to "PROGRAM VERSION". +configuration+
      # maps each config file key to its documentation for the root page's CONFIGURATION
      # section; the caller supplies it because the keys belong to the settings loader.
      def initialize(registry, date:, source: nil, environment: DEFAULT_ENVIRONMENT, configuration: {})
        @registry = registry
        @date = date
        @source = source || "#{registry.program} #{registry.version}"
        @environment = environment
        @configuration = configuration
      end

      # Every page keyed by file name: "slipway.1", "slipway-get.1", "slipway-config-view.1", ...
      def pages
        paths.to_h { |path| [file_name(path), page(path)] }
      end

      # The page for the command reached through +path+; an empty path is the root page.
      def page(path)
        command, = @registry.resolve(path)
        lines = path.empty? ? root_page(command) : command_page(command, path)
        "#{lines.join("\n")}\n"
      end

      private

      def paths(command = @registry.root, path = [])
        [path, *command.visible_subcommands.flat_map { paths(it, [*path, it.name]) }]
      end

      def file_name(path) = "#{page_name(path)}.#{SECTION}"

      def page_name(path) = [@registry.program, *path].join('-')

      # The .TH fields are quoted verbatim: an escaped date is one mandoc cannot parse.
      def header(path)
        fields = [page_name(path).upcase, SECTION, @date, @source, MANUAL].map { %("#{it.gsub('"', '\\(dq')}") }
        [%(.\\" Generated by #{@registry.program} #{@registry.version}. Do not edit.), ".TH #{fields.join(' ')}"]
      end

      def root_page(root)
        [
          *header([]),
          *name_section([], @registry.description.delete_suffix('.')),
          *root_synopsis,
          '.SH DESCRIPTION', *Roff.paragraphs(root.description),
          *commands_section(root),
          *options_section(@registry.globals),
          *tagged_section('ENVIRONMENT', @environment),
          *files_section,
          *tagged_section('CONFIGURATION', @configuration),
          *tagged_section('EXIT STATUS', EXIT_STATUSES),
          *see_also(paths.drop(1))
        ]
      end

      def command_page(command, path)
        [
          *header(path),
          *name_section(path, command.summary),
          *synopsis(command, path),
          '.SH DESCRIPTION', *Roff.paragraphs(command.description),
          *commands_section(command),
          *options_section(command.options),
          *examples_section(command.examples),
          *see_also(related(path))
        ]
      end

      def root_synopsis
        ['.SH SYNOPSIS', ".SY #{Roff.argument(@registry.program)}", '.RI [ flags ]', '.I COMMAND', '.RI [ ARGS... ]\\&',
         '.YS']
      end

      def name_section(path, summary)
        ['.SH NAME', "#{Roff.text(page_name(path))} \\- #{Roff.text(summary)}"]
      end

      def synopsis(command, path)
        ['.SH SYNOPSIS', ".SY #{Roff.argument([@registry.program, *path].join(' '))}", *synopsis_args(command), '.YS']
      end

      # Required options, then the positionals (or the command's own usage text), then [flags].
      def synopsis_args(command)
        required = command.options.select(&:required)
        options = required.flat_map { [".B #{Roff.text(it.switches.first)}", ".I #{it.argument}"] }
        [*options, *positional_args(command), '.RI [ flags ]']
      end

      def positional_args(command)
        return ['.I COMMAND'] if command.group?
        return [".I #{Roff.argument(command.usage)}\\&"] if command.usage

        command.positionals.map { positional_arg(it) }
      end

      # Both forms end with \& so a trailing period is not read as the end of a sentence.
      def positional_arg(positional)
        token = Roff.text(positional.variadic ? "#{positional.name}..." : positional.name)
        positional.required ? ".I #{token}\\&" : ".RI [ #{token} ]\\&"
      end

      # Subcommands under .SS headings per section when there is more than one section.
      def commands_section(command)
        sections = command.sections
        return [] if sections.empty?

        width = command.visible_subcommands.map { it.name.size }.max + 2
        entries = sections.flat_map do |section, commands|
          heading = sections.size > 1 ? [Roff.subheading(section)] : []
          heading + commands.flat_map { Roff.tagged(Roff.bold(it.name), it.summary, indent: width) }
        end
        ['.SH COMMANDS', *entries]
      end

      def options_section(options)
        return [] if options.empty?

        ['.SH OPTIONS', *options.flat_map { Roff.tagged(option_label(it), it.description_parts.join(' ')) }]
      end

      def option_label(option)
        switches = option.switches.map { Roff.bold(it) }.join(', ')
        return switches if option.flag?

        argument = Roff.italic(option.argument)
        option.optional ? "#{switches}[=#{argument}]" : "#{switches} #{argument}"
      end

      def examples_section(examples)
        return [] if examples.empty?

        blocks = examples.map do |example|
          ['.EX', Roff.text("# #{example.comment}"), Roff.text("#{@registry.program} #{example.command}"), '.EE']
        end
        ['.SH EXAMPLES', *blocks.flat_map.with_index { |block, index| index.zero? ? block : ['.PP', *block] }]
      end

      def tagged_section(title, entries)
        [Roff.heading(title), *entries.flat_map { |key, meaning| Roff.tagged(Roff.bold(key), meaning) }]
      end

      def files_section
        program = @registry.program
        [
          '.SH FILES',
          *Roff.tagged(Roff.italic("$XDG_CONFIG_HOME/#{program}/config.yaml"),
                       'Configuration file; see CONFIGURATION. Also set by --config or SLIPWAY_CONFIG.'),
          *Roff.tagged(Roff.italic("$XDG_DATA_HOME/#{program}/"),
                       'Registry data: groups/NAME.yaml and projects/GROUP/NAME.yaml. Also set by SLIPWAY_DATA_HOME.')
        ]
      end

      # A command page points back at the root page and, when nested, at its group page.
      def related(path)
        [[], *(path.size > 1 ? [path[0...-1]] : [])]
      end

      def see_also(paths)
        [Roff.heading('SEE ALSO'), paths.map { Roff.reference(page_name(it)) }.join(",\n")]
      end
    end
  end
end
