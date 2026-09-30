# frozen_string_literal: true

module Slipway
  module Output
    # The plaintext layout of kubectl explain: the KIND line, the FIELD line when a field was named,
    # its DESCRIPTION wrapped at 80 columns and the FIELDS under it, each with its description or,
    # with `recursive`, as a tree of names and types. The types line up in one column, where
    # kubectl puts a tab. Colors follow kubecolor: the labels, the field names and the -required-
    # mark.
    class Explain
      # `description` is the text to print whole; `fields` are the fields under this one.
      Field = Data.define(:name, :type, :required, :description, :fields)

      WIDTH = 80
      INDENT = '  '
      GAP = 3
      REQUIRED = '-required-'

      def initialize(context)
        @context = context
      end

      # `named` prints the FIELD line, for a field below the resource type itself.
      def render(kind:, field:, named: false, recursive: false)
        sections = ["#{label('KIND')} #{kind}"]
        sections << "#{label('FIELD')} #{field.name} #{type(field)}" if named
        sections << "#{label('DESCRIPTION')}\n#{paragraph(field.description, INDENT * 2)}"
        sections << fields(field, recursive) unless field.fields.empty?
        "#{sections.join("\n\n")}\n"
      end

      def print(**) = @context.print(render(**))

      private

      def label(word) = "#{@context.style.paint_cycle(:describe_keys, 0, word)}:"

      def type(field)
        mark = " #{@context.paint(:explain_required, REQUIRED)}" if field.required
        "<#{field.type}>#{mark}"
      end

      # Each row is [depth, field], with depth 1 for the fields right under the one explained.
      def fields(field, recursive)
        rows = recursive ? tree(field.fields, 1) : field.fields.map { [1, it] }
        width = rows.map { |depth, child| (INDENT * depth).size + child.name.size }.max + GAP
        entries = rows.map { |depth, child| entry(child, depth, width, recursive) }
        "#{label('FIELDS')}\n#{entries.join(recursive ? "\n" : "\n\n")}"
      end

      def tree(fields, depth) = fields.flat_map { [[depth, it], *tree(it.fields, depth + 1)] }

      # A recursive listing cycles the name colors by depth, as kubecolor does.
      def entry(field, depth, width, recursive)
        indent = INDENT * depth
        name = @context.style.paint_cycle(:describe_keys, recursive ? depth - 1 : 0, field.name)
        line = "#{indent}#{name}#{' ' * (width - indent.size - field.name.size)}#{type(field)}"
        recursive ? line : "#{line}\n#{paragraph(field.description, indent + INDENT)}"
      end

      def paragraph(text, indent) = wrap(text, WIDTH - indent.size).map { "#{indent}#{it}" }.join("\n")

      # A word longer than the width gets a line of its own rather than being cut.
      def wrap(text, width)
        text.split.each_with_object([]) do |word, lines|
          if lines.empty? || lines.last.size + word.size >= width
            lines << word
          else
            lines[-1] = "#{lines.last} #{word}"
          end
        end
      end
    end
  end
end
