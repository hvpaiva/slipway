# frozen_string_literal: true

module Slipway
  module CLI
    # Alignment is computed on plain text and color applied afterwards, so ANSI escapes
    # never skew columns.
    class HelpRenderer
      COMMAND_COLUMN = 16
      FLAG_COLUMN = 30
      GAP = '   '
      INDENT = '  '
      FLAGS = '[flags]'
      # Width of "-x, ", so long-only options line up with the long form of short ones.
      SHORT_PREFIX = ' ' * 4

      def initialize(registry, style)
        @registry = registry
        @style = style
      end

      def root
        join([
               @registry.root.description,
               *command_sections(@registry.root),
               option_section('Options', @registry.globals),
               usage("#{@registry.program} #{FLAGS} COMMAND [ARGS...]"),
               command_trailer([])
             ])
      end

      def command(command, path)
        join([
               command.description,
               examples(command.examples),
               *command_sections(command),
               option_section('Options', command.options),
               usage(command_usage(command, path)),
               trailer(command, path)
             ])
      end

      private

      def join(sections) = "#{sections.compact.join("\n\n")}\n"

      def header(text) = @style.paint(:help_header, "#{text}:")

      def command_sections(command)
        command.sections.map do |section, commands|
          width = [COMMAND_COLUMN, *commands.map { it.name.size + GAP.size }].max
          rows = commands.map { "#{INDENT}#{it.name.ljust(width)}#{it.summary}" }
          "#{header(section)}\n#{rows.join("\n")}"
        end
      end

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

      def option_section(title, options)
        return nil if options.empty?

        labels = options.map { padded_label(it) }
        width = [labels.map(&:size).max, FLAG_COLUMN].min
        rows = options.zip(labels).map { |option, label| option_row(option, label, width) }
        "#{header(title)}\n#{rows.join("\n")}"
      end

      def padded_label(option) = option.short ? option.label : "#{SHORT_PREFIX}#{option.label}"

      def option_row(option, label, width)
        painted = paint_label(label)
        text = option.description_parts.join(' ')
        return "#{INDENT}#{painted}\n#{INDENT}#{' ' * width}#{GAP}#{text}" if label.size > width

        "#{INDENT}#{painted}#{' ' * (width - label.size)}#{GAP}#{text}"
      end

      # The padding of a long-only label stays outside the escape sequence.
      def paint_label(label)
        stripped = label.lstrip
        "#{label[0, label.size - stripped.size]}#{@style.paint(:help_flag, stripped)}"
      end

      def usage(line) = "#{header('Usage')}\n#{INDENT}#{line}"

      # Required options come before the positionals, as kubectl writes `apply -f FILENAME`;
      # `[flags]` is always there because the global options apply to every command.
      def command_usage(command, path)
        required = command.options.select(&:required).map { "#{it.switches.first} #{it.argument}" }
        [@registry.program, *path, *required, command.usage_args, FLAGS].reject(&:empty?).join(' ')
      end

      def trailer(command, path)
        lines = []
        lines << command_trailer(path) if command.group?
        lines << %(Use "#{@registry.program} --help" for a list of global options (applies to all commands).)
        lines.join("\n")
      end

      def command_trailer(path)
        %(Use "#{[@registry.program, *path].join(' ')} <command> --help" for more information about a given command.)
      end
    end
  end
end
