# frozen_string_literal: true

module Slipway
  module Output
    # Renders rows the way kubectl prints resources: uppercase headers, left-aligned
    # columns three spaces apart, no borders, and no trailing whitespace. Widths come from
    # the plain text, so color never shifts a column. Cells are never wrapped.
    class Table
      NONE = '<none>'
      GAP = '   '

      # +headers+ names the columns. +roles+, when given, is called with the header and the
      # plain cell text and may return a theme role that replaces the column color.
      def initialize(context, headers:, show_headers: true, roles: nil)
        @context = context
        @headers = headers
        @show_headers = show_headers
        @roles = roles
      end

      # Every line of the table, each ending in a newline; empty when there is nothing to show.
      def render(rows)
        cells = rows.map { |row| @headers.each_index.map { text(row[it]) } }
        widths = column_widths(cells)
        lines = cells.map { row_line(it, widths) }
        lines.unshift(header_line(widths)) if @show_headers
        lines.map { "#{it}\n" }.join
      end

      # Writes the rendered table to the context's stdout.
      def print(rows) = @context.print(render(rows))

      private

      def text(value)
        value = value.to_s
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

        @context.style.paint_cycle(:table_columns, index, cell)
      end
    end
  end
end
