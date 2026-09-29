# frozen_string_literal: true

require 'fileutils'

# Compares rendered text with a checked-in file. UPDATE_GOLDEN=1 rewrites the fixtures under
# test/fixtures/golden and skips; otherwise a mismatch fails with a unified diff made in Ruby.
module GoldenHelper
  FIXTURES = File.expand_path('../fixtures/golden', __dir__)
  UPDATE_VARIABLE = 'UPDATE_GOLDEN'

  # +name+ is the fixture's path under test/fixtures/golden.
  def assert_golden(name, actual)
    path = File.join(FIXTURES, name)
    if update_golden?
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, actual)
      skip "wrote #{relative(path)}"
    end

    assert_path_exists path, "#{relative(path)} is missing; run the suite once with #{UPDATE_VARIABLE}=1"
    assert_text_file(path, actual, regenerate: "rerun with #{UPDATE_VARIABLE}=1 if the change is intended")
  end

  # Fails with a unified diff when +actual+ differs from the file at +path+; +regenerate+
  # tells the reader how to refresh that file.
  def assert_text_file(path, actual, regenerate:)
    expected = File.read(path)
    return pass if expected == actual

    flunk "#{relative(path)} differs from the rendered text (#{regenerate}):\n" \
          "#{Diff.unified(expected, actual, from: relative(path), to: 'rendered')}"
  end

  def update_golden? = !ENV.fetch(UPDATE_VARIABLE, '').empty?

  def relative(path) = path.delete_prefix("#{File.expand_path('../..', __dir__)}/")

  # A line-based unified diff with three lines of context, built on a longest common
  # subsequence table so it reads the same on every machine.
  module Diff
    CONTEXT = 3
    MARKS = { same: ' ', del: '-', add: '+' }.freeze
    NO_NEWLINE = "\n\\ No newline at end of file\n"

    module_function

    def unified(expected, actual, from:, to:)
      old_lines = expected.lines
      new_lines = actual.lines
      edits = edits(old_lines, new_lines)
      hunks = hunks(edits).map { render(edits[it], old_lines, new_lines) }
      "--- #{from}\n+++ #{to}\n#{hunks.join}"
    end

    # Every line as [:same | :del | :add, index in old, index in new], read off the LCS table.
    def edits(old_lines, new_lines)
      table = lcs_table(old_lines, new_lines)
      edits = []
      old = new = 0
      while old < old_lines.size || new < new_lines.size
        kind = step(table, old_lines, new_lines, old, new)
        edits << [kind, old, new]
        old += 1 unless kind == :add
        new += 1 unless kind == :del
      end
      edits
    end

    def step(table, old_lines, new_lines, old, new)
      return :same if old < old_lines.size && new < new_lines.size && old_lines[old] == new_lines[new]
      return :add if new < new_lines.size && (old == old_lines.size || table[old][new + 1] >= table[old + 1][new])

      :del
    end

    # table[old][new] is the length of the longest common subsequence of old_lines[old..] and
    # new_lines[new..]; the last row and column stay zero.
    def lcs_table(old_lines, new_lines)
      below = Array.new(new_lines.size + 1, 0)
      rows = old_lines.reverse.map do |old_line|
        below = lcs_row(old_line, new_lines, below)
      end
      [*rows.reverse, Array.new(new_lines.size + 1, 0)]
    end

    def lcs_row(old_line, new_lines, below)
      row = Array.new(new_lines.size + 1, 0)
      (new_lines.size - 1).downto(0) do |new|
        row[new] = old_line == new_lines[new] ? below[new + 1] + 1 : [below[new], row[new + 1]].max
      end
      row
    end

    # The ranges of edits worth printing: every change plus its context, merged when close.
    def hunks(edits)
      changed = edits.each_index.reject { edits[it].first == :same }
      changed.slice_when { |before, after| after - before > (CONTEXT * 2) + 1 }.map do |group|
        ([group.first - CONTEXT, 0].max)..([group.last + CONTEXT, edits.size - 1].min)
      end
    end

    def render(slice, old_lines, new_lines)
      header = "@@ -#{position(slice, :add, 1)} +#{position(slice, :del, 2)} @@\n"
      body = slice.map do |kind, old, new|
        "#{MARKS.fetch(kind)}#{line(kind == :add ? new_lines[new] : old_lines[old])}"
      end
      header + body.join
    end

    # "start,count" of one side of a hunk, counting every edit except +excluded+ ones.
    def position(slice, excluded, index)
      count = slice.count { it.first != excluded }
      "#{slice.first[index] + (count.zero? ? 0 : 1)},#{count}"
    end

    def line(text) = text.end_with?("\n") ? text : "#{text}#{NO_NEWLINE}"
  end
end
