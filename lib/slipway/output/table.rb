# frozen_string_literal: true

module Slipway
  module Output
    # Widths come from the plain text, so color never shifts a column.
    class Table
      NONE = '<none>'
      GAP = '   '

      # +roles+ is called with the header and the plain cell text and may return a theme role
      # that replaces the column color. +color_offset+ leading columns stay out of the color cycle.
      def initialize(context, headers:, show_headers: true, roles: nil, color_offset: 0)
        @context = context
        @headers = headers
        @show_headers = show_headers
        @roles = roles
        @color_offset = color_offset
      end

      def render(rows)
        cells = rows.map { |row| @headers.each_index.map { text(row[it]) } }
        widths = column_widths(cells)
        lines = cells.map { row_line(it, widths) }
        lines.unshift(header_line(widths)) if @show_headers
        lines.map { "#{it}\n" }.join
      end

      def print(rows) = @context.print(render(rows))

      private

      def text(value)
        value = Output.plain(value)
        value.empty? ? NONE : value
      end

      def column_widths(cells)
        @headers.each_index.map do |index|
          sizes = cells.map { it[index].size }
          sizes << @headers[index].to_s.size if @show_headers
          sizes.max
        end
      end

      def header_line(widths)
        titles = @headers.each_with_index.map { |header, index| header.to_s.upcase.ljust(widths[index]) }
        @context.paint(:table_header, titles.join(GAP).rstrip)
      end

      def row_line(cells, widths)
        painted = cells.each_with_index.map do |cell, index|
          paint_cell(cell, index) + (' ' * (widths[index] - cell.size))
        end
        painted.join(GAP).rstrip
      end

      def paint_cell(cell, index)
        return @context.paint(:none, cell) if cell == NONE

        role = @roles&.call(@headers[index], cell)
        return @context.paint(role, cell) if role

        @context.style.paint_cycle(:table_columns, index - @color_offset, cell)
      end
    end
  end
end
