# frozen_string_literal: true

require 'shellwords'

# Reads the ```console blocks of a Markdown file as transcripts: each "$ slipway ..." line is a
# command, the lines up to the next one are what it prints, and blank lines at the end of that
# output only separate it from the next command. A block that cannot run in a sandbox sits
# right under "<!-- not run: REASON -->" and keeps the reason instead of its commands.
module ReadmeExamples
  Block = Data.define(:line, :commands, :not_run)

  Command = Data.define(:line, :text, :expected) do
    def argv = Shellwords.split(text).drop(1)
  end

  class Error < StandardError; end

  FENCE = '```console'
  # Any other fence of a console block, indented, titled or in another letter case, is an error
  # rather than a block that is never run.
  FENCE_LIKE = /\A\s*(?:`{3,}|~{3,})\s*console\b/i
  CLOSE = '```'
  PROMPT = '$ '
  PROGRAM = 'slipway'
  NOT_RUN = /\A<!-- not run: (?<reason>.+) -->\z/
  # What a shell would expand, redirect or run before slipway starts, including the ! that starts
  # history expansion in an interactive bash or zsh unless a space, = or ( follows it.
  # Single-quoted text, and double-quoted text without $, `, \ or !, reaches the program as
  # written, so it is left out.
  QUOTED = /'[^']*'|"[^"$`\\!]*"/
  SHELL_SYNTAX = /[|&;<>()$`*?\[\]{}\\]|(?:\A|\s)[~#]|!(?![\s=(]|\z)/
  # What changes from one run to the next: times, commit ids and the seconds since the examples
  # registered a resource. The story dates its commits and fetches, so ages in hours and days
  # are compared as written. A commit id keeps its length, so a short id in place of a full one
  # is a mismatch. YAML quotes an id that reads as a number (all digits, or digits around one
  # e), so a quoted id and a bare one are the same value.
  VOLATILE = {
    '<time>' => /\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ/,
    '<commit>' => /'[0-9a-f]{40}'|\b[0-9a-f]{40}\b/,
    '<sha>' => /'[0-9a-f]{7}'|\b[0-9a-f]{7}\b/,
    '<age>' => /\b\d+s\b/
  }.freeze

  module_function

  def parse(text, file: 'README.md')
    lines = text.lines(chomp: true)
    lines.each_index.filter_map do |index|
      case lines[index]
      when NOT_RUN
        raise Error, "#{file}:#{index + 1}: a not-run marker belongs above a #{FENCE} line" if lines[index + 1] != FENCE
      when FENCE then block(lines, index, file)
      when FENCE_LIKE
        raise Error, "#{file}:#{index + 1}: a console block opens with #{FENCE} alone, at the start of the line"
      end
    end
  end

  # A value padded to a column keeps the column's width: the placeholder and its padding fill
  # the space the value and its padding took, so a table lines up the same whether an age reads
  # 9s or 10s. Anywhere else the placeholder stands alone.
  def normalize(text)
    VOLATILE.reduce(text) do |result, (placeholder, pattern)|
      result.gsub(/#{pattern}(?: {2,}(?=\S))?/) { it.end_with?(' ') ? placeholder.ljust(it.length) : placeholder }
    end
  end

  def block(lines, start, file)
    body = lines.drop(start + 1).take_while { it != CLOSE }
    raise Error, "#{file}:#{start + 1}: the console block is never closed" if start + 1 + body.size == lines.size

    not_run = NOT_RUN.match(lines[start - 1])&.[](:reason) if start.positive?
    Block.new(line: start + 1, commands: not_run ? [] : commands(body, start + 2, file), not_run:)
  end

  def commands(body, first_line, file)
    unless body.empty? || body.first.start_with?(PROMPT)
      raise Error, "#{file}:#{first_line}: a console block starts with a #{PROMPT.strip} line"
    end

    starts = body.each_index.select { body[it].start_with?(PROMPT) }
    starts.zip(starts.drop(1)).map do |start, stop|
      output = body[(start + 1)...(stop || body.size)]
      output = output[0...-1] while output.last&.empty?
      command(body[start].delete_prefix(PROMPT), first_line + start, output, file)
    end
  end

  def command(text, line, output, file)
    where = "#{file}:#{line}: #{text}"
    raise Error, "#{where} needs a shell, and a console block runs #{PROGRAM} without one" if shell?(text)
    raise Error, "#{where} does not run #{PROGRAM}" unless words(text, where).first == PROGRAM

    Command.new(line:, text:, expected: output.map { "#{it}\n" }.join)
  end

  def shell?(text) = text.gsub(QUOTED, '').match?(SHELL_SYNTAX)

  def words(text, where)
    Shellwords.split(text)
  rescue ArgumentError
    raise Error, "#{where} leaves a quote open"
  end

  private_class_method :block, :commands, :command, :shell?, :words
end
