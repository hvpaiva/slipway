# frozen_string_literal: true

require 'test_helper'

class ReadmeExamplesTest < Minitest::Test
  Block = ReadmeExamples::Block
  Command = ReadmeExamples::Command

  ALONE = 'a console block opens with ```console alone, at the start of the line'
  TRANSCRIPT = <<~MARKDOWN
    Create a group, then list it.

    ```console
    $ slipway create group work --description "Day job"
    group/work created

    $ slipway get groups -l 'tier in (web)'
    NAME   AGE
    work   1s
    $ slipway delete group work -o name
    ```

    ```sh
    $ slipway get projects | head
    ```
  MARKDOWN

  def test_each_command_expects_the_lines_up_to_the_next_one
    commands = [Command.new(line: 4, text: 'slipway create group work --description "Day job"',
                            expected: "group/work created\n"),
                Command.new(line: 7, text: "slipway get groups -l 'tier in (web)'",
                            expected: "NAME   AGE\nwork   1s\n"),
                Command.new(line: 10, text: 'slipway delete group work -o name', expected: '')]

    assert_equal [Block.new(line: 3, commands:, not_run: nil)], ReadmeExamples.parse(TRANSCRIPT)
  end

  def test_arguments_are_split_the_way_a_shell_splits_them
    command = ReadmeExamples.parse(TRANSCRIPT).first.commands.first

    assert_equal ['create', 'group', 'work', '--description', 'Day job'], command.argv
  end

  def test_a_marked_block_keeps_its_reason_instead_of_its_commands
    markdown = "<!-- not run: needs a real remote -->\n```console\n$ slipway fetch\n```\n"

    assert_equal [Block.new(line: 2, commands: [], not_run: 'needs a real remote')], ReadmeExamples.parse(markdown)
  end

  def test_a_marker_away_from_a_console_block_is_an_error
    error = assert_raises(ReadmeExamples::Error) do
      ReadmeExamples.parse("<!-- not run: needs a real remote -->\n\n```console\n$ slipway fetch\n```\n")
    end

    assert_equal 'README.md:1: a not-run marker belongs above a ```console line', error.message
  end

  def test_malformed_blocks_are_errors_naming_the_line
    {
      "```console title\n$ slipway get\n```\n" => "1: #{ALONE}",
      "1. Step\n\n   ```console\n   $ slipway get\n   ```\n" => "3: #{ALONE}",
      "````console\n$ slipway get\n````\n" => "1: #{ALONE}",
      "~~~console\n$ slipway get\n~~~\n" => "1: #{ALONE}",
      "``` console\n$ slipway get\n```\n" => "1: #{ALONE}",
      "```Console\n$ slipway get\n```\n" => "1: #{ALONE}",
      "text\n```console\n$ slipway get\n" => '2: the console block is never closed',
      "```console\nNAME\n$ slipway get\n```\n" => '2: a console block starts with a $ line',
      "```console\n$ git status\n```\n" => '2: git status does not run slipway',
      "```console\n$ slipway get 'projects\n```\n" => "2: slipway get 'projects leaves a quote open"
    }.each do |markdown, message|
      error = assert_raises(ReadmeExamples::Error) { ReadmeExamples.parse(markdown, file: 'DOC.md') }

      assert_equal "DOC.md:#{message}", error.message
    end
  end

  def test_a_command_that_needs_a_shell_is_an_error
    ['slipway get projects | head', 'slipway get projects > out', 'slipway create project x --path ~/x',
     'slipway get -n "$GROUP"', 'slipway get projects # every one', 'slipway get pro*',
     'slipway get projects -l !kind', 'slipway get projects -l "!kind"'].each do |text|
      error = assert_raises(ReadmeExamples::Error) { ReadmeExamples.parse("```console\n$ #{text}\n```\n") }

      assert_equal "README.md:2: #{text} needs a shell, and a console block runs slipway without one", error.message
    end
  end

  def test_quoted_text_reaches_slipway_as_written
    text = %(slipway create project x --path '~/x' -l 'a in (b,c)' --description "it's #1")

    assert_equal ['create', 'project', 'x', '--path', '~/x', '-l', 'a in (b,c)', '--description', "it's #1"],
                 ReadmeExamples.parse("```console\n$ #{text}\n```\n").first.commands.first.argv
  end

  def test_a_bang_the_shell_leaves_alone_reaches_slipway_as_written
    text = %(slipway get projects -l '!kind' --field-selector status.state!=Clean,"metadata.name!=x")

    assert_equal ['get', 'projects', '-l', '!kind', '--field-selector', 'status.state!=Clean,metadata.name!=x'],
                 ReadmeExamples.parse("```console\n$ #{text}\n```\n").first.commands.first.argv
  end

  def test_normalize_replaces_ages_in_seconds_commit_ids_and_times_but_keeps_the_columns
    readme = "NAME   FETCHED   AGE   HEAD      LAST-COMMIT\nhldr   5h        1s    e001395   32h\n" \
             "Created:  2026-09-29T07:15:35Z\n  origin/main 1c2d3e4..5f6a7b8\nHash:  #{'e' * 40}\n"
    run = "NAME   FETCHED   AGE   HEAD      LAST-COMMIT\nhldr   5h        12s   0a9b8c7   32h\n" \
          "Created:  2026-10-01T00:00:00Z\n  origin/main 0000000..fffffff\nHash:  #{'0' * 40}\n"

    assert_equal ReadmeExamples.normalize(readme), ReadmeExamples.normalize(run)
    assert_equal "hldr   5h        <age> <sha>     32h\n", ReadmeExamples.normalize(run).lines[1]
  end

  def test_normalize_leaves_everything_else_as_written
    text = "augur   Dirty   <never>   5h   2d   32h   4m12s\n3 projects: 1 fetched, 2 unchanged\n" \
           "Path:  ~/dev/augur\n  origin/main 1c2d3e4f5a6b..5f6a7b8c9d0e\n"

    assert_equal text, ReadmeExamples.normalize(text)
  end

  def test_normalize_keeps_the_length_of_a_commit_id
    refute_equal ReadmeExamples.normalize("Hash:  #{'e' * 40}\n"), ReadmeExamples.normalize("Hash:  #{'e' * 7}\n")
  end
end
