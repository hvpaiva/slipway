# frozen_string_literal: true

module Slipway
  module CLI
    # Alignment and wrapping are computed on plain text and color applied afterwards, so ANSI
    # escapes never skew columns.
    class HelpRenderer
      LABEL_COLUMN = 30
      GAP = '  '
      INDENT = '  '
      BLOCK_INDENT = ' ' * 10
      OPTIONS = '[OPTIONS]'
      # Width of "-x, ", so long-only options line up with the long form of short ones.
      SHORT_PREFIX = ' ' * 4
      MAX_WIDTH = 100
      MIN_TEXT_WIDTH = 20
      BULLET = /\A\s*\*\s+/

      Entry = Data.define(:label, :painted, :text, :notes) do
        def initialize(label:, text:, painted: label, notes: []) = super
      end

      def initialize(registry, style, width: nil)
        @registry = registry
        @style = style
        @width = [width || MAX_WIDTH, MAX_WIDTH].min
      end

      def root(long: true)
        root = @registry.root
        join([
               long ? paragraphs(root.description) : root.summary,
               usage("#{@registry.program} #{OPTIONS} #{root.usage_args}"),
               command_section(root),
               option_section(@registry.globals, long:),
               *(long ? root.glossaries.map { glossary(it) } : []),
               lines(command_trailer([]))
             ])
      end

      def command(command, path, long: true)
        join([
               long ? paragraphs(command.description) : command.summary,
               usage(command_usage(command, path)),
               command_section(command),
               argument_section(command.positionals, long:),
               option_section(command.options + help_options, long:),
               *(long ? reference(command) : []),
               trailer(command, path)
             ])
      end

      private

      def join(sections) = "#{sections.compact.join("\n\n")}\n"

      def header(text) = @style.paint(:help_header, "#{text}:")

      def help_options = @registry.globals.select { it.key == :help }

      def usage(line) = "#{header('Usage')} #{line}"

      def command_usage(command, path)
        required = command.options.select(&:required).map { "#{it.switches.first} <#{it.argument}>" }
        [@registry.program, *path, OPTIONS, *required, command.usage_args].reject(&:empty?).join(' ')
      end

      def command_section(command)
        sections = command.sections
        return nil if sections.empty?

        width = command.visible_subcommands.map { it.name.size }.max
        sections.map do |section, commands|
          "#{header(section)}\n#{rows(commands.map { Entry.new(label: it.name, text: it.summary) }, width:)}"
        end.join("\n\n")
      end

      def argument_section(positionals, long:)
        return nil if positionals.empty?

        entries = positionals.map do |positional|
          Entry.new(label: positional.usage, notes: positional.notes,
                    text: long ? positional.description : positional.short_description)
        end
        "#{header('Arguments')}\n#{long ? blocks(entries) : rows(entries)}"
      end

      def option_section(options, long:)
        return nil if options.empty?

        entries = options.map do |option|
          label = option.short ? option.label : "#{SHORT_PREFIX}#{option.label}"
          Entry.new(label:, painted: paint_label(label), notes: option.notes,
                    text: long ? option.description : option.short_description)
        end
        "#{header('Options')}\n#{long ? blocks(entries) : rows(entries)}"
      end

      # The padding of a long-only label stays outside the escape sequence.
      def paint_label(label)
        stripped = label.lstrip
        "#{label[0, label.size - stripped.size]}#{@style.paint(:help_flag, stripped)}"
      end

      def rows(entries, width: [entries.map { it.label.size }.max, LABEL_COLUMN].min)
        hanging = INDENT + (' ' * (width + GAP.size))
        entries.map { row(it, width, hanging) }.join("\n")
      end

      def row(entry, width, hanging)
        text = wrap([entry.text, *entry.notes].compact.join(' '), @width - hanging.size)
        label = "#{INDENT}#{entry.painted}"
        return [label, *text.map { "#{hanging}#{it}" }].join("\n") if entry.label.size > width || text.empty?

        first, *rest = text
        ["#{label}#{' ' * (width - entry.label.size)}#{GAP}#{first}", *rest.map { "#{hanging}#{it}" }].join("\n")
      end

      def blocks(entries)
        entries.map do |entry|
          body = [entry.text && indented(entry.text, BLOCK_INDENT),
                  entry.notes.empty? ? nil : entry.notes.map { indented(it, BLOCK_INDENT) }.join("\n")].compact
          ["#{INDENT}#{entry.painted}", body.join("\n\n")].reject(&:empty?).join("\n")
        end.join("\n\n")
      end

      def reference(command)
        [*command.glossaries.map { glossary(it) }, exit_statuses(command.exit_statuses), examples(command.examples)]
      end

      def exit_statuses(statuses)
        return nil if statuses.empty?

        "#{header('Exit Status')}\n#{terms(statuses)}"
      end

      def glossary(glossary)
        intro = glossary.intro && "#{indented(glossary.intro, INDENT)}\n\n"
        "#{header(glossary.title)}\n#{intro}#{terms(glossary.entries)}"
      end

      def terms(entries) = rows(entries.map { |term, meaning| Entry.new(label: term, text: meaning) })

      def examples(examples)
        return nil if examples.empty?

        blocks = examples.map do |example|
          "#{INDENT}#{@style.paint(:help_comment, "# #{example.comment}")}\n#{INDENT}#{shell_line(example.command)}"
        end
        "#{header('Examples')}\n#{blocks.join("\n\n")}"
      end

      def shell_line(command)
        program, *words = "#{@registry.program} #{command}".split
        painted = words.map { it.start_with?('-') ? @style.paint(:help_flag, it) : it }
        [@style.paint(:help_command, program), *painted].join(' ')
      end

      def trailer(command, path)
        lines = []
        lines << command_trailer(path) if command.group?
        lines << %(Use "#{@registry.program} --help" for a list of global options (applies to all commands).)
        lines(*lines)
      end

      def command_trailer(path)
        %(Use "#{[@registry.program, *path].join(' ')} <COMMAND> --help" for more information about a given command.)
      end

      def lines(*sentences) = sentences.map { indented(it, '') }.join("\n")

      def paragraphs(text) = text.split(/\n{2,}/).map { indented(it, '') }.join("\n\n")

      def indented(text, indent)
        text.lines(chomp: true).flat_map do |line|
          lead = line[BULLET] || line[/\A\s*/]
          first, *rest = wrap(line.delete_prefix(lead), @width - indent.size - lead.size)
          ["#{indent}#{lead}#{first}", *rest.map { "#{indent}#{' ' * lead.size}#{it}" }]
        end.join("\n")
      end

      def wrap(text, width)
        width = [width, MIN_TEXT_WIDTH].max
        text.split.each_with_object([]) do |word, wrapped|
          if wrapped.empty? || wrapped.last.size + 1 + word.size > width
            wrapped << word
          else
            wrapped[-1] = "#{wrapped.last} #{word}"
          end
        end
      end
    end
  end
end
