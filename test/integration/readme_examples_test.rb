# frozen_string_literal: true

require 'test_helper'

class ReadmeExamplesIntegrationTest < Minitest::Test
  include IntegrationHelper

  README = File.join(ROOT, 'README.md')
  # A malformed block fails one test rather than the loading of every test file.
  BLOCKS, MALFORMED = begin
    [ReadmeExamples.parse(File.read(README)), nil]
  rescue ReadmeExamples::Error => e
    [[], e.message]
  end
  # The story's remotes are local paths, which git reaches over the file transport. Only the
  # commands that fetch are given it, so every other command runs with the settings a reader has.
  PROTOCOLS = { 'SLIPWAY_PROTOCOLS' => 'ssh:https:file' }.freeze
  SYNC_STDOUT = File.join(ROOT, 'test', 'support', 'preload', 'sync_stdout.rb')

  class << self
    attr_accessor :transcript
  end

  BLOCKS.each do |block|
    define_method("test_console_block_at_line_#{block.line}") do
      skip "README.md:#{block.line} is marked not run: #{block.not_run}" if block.not_run
      skip_unless_fetch_lists_refs if block.commands.any? { fetches?(it) }

      assert_prints_what_the_readme_shows(block)
    end
  end

  def test_the_console_blocks_parse_and_some_run
    assert_nil MALFORMED
    refute_empty BLOCKS.reject(&:not_run)
  end

  def test_stdout_stays_ahead_of_a_later_error_as_on_a_terminal
    with_home do |env|
      slipway!('create', 'project', 'notes', '--path', env.fetch('HOME'), env:)
      command = ReadmeExamples::Command.new(line: 0, text: 'slipway get projects notes ghost', expected: '')

      assert_equal(%w[NAME notes error:], output(command, env).lines.map { it.split.first })
    end
  end

  private

  def assert_prints_what_the_readme_shows(block)
    mismatches = block.commands.zip(transcript.fetch(block)).filter_map { mismatch(*it) }
    return pass if mismatches.empty?

    flunk mismatches.join("\n")
  end

  # The story runs once per process, top to bottom, because each block starts from the state
  # the blocks above it left.
  def transcript = self.class.transcript ||= record

  def record
    with_home do |env|
      ReadmeStory.new(env.fetch('HOME')).build
      BLOCKS.to_h { |block| [block, block.commands.map { output(it, env) }] }
    end
  end

  # stdout and stderr share one pipe, so the lines interleave as a terminal shows them.
  def output(command, env)
    env = env.merge(PROTOCOLS) if fetches?(command)
    text, = Open3.capture2e(env, RbConfig.ruby, '-w', '-r', SYNC_STDOUT, '-I', LIB, EXE, *command.argv,
                            unsetenv_others: true)
    ReadmeExamples.normalize(text)
  end

  def fetches?(command) = %w[fetch sync].include?(command.argv.first)

  def mismatch(command, actual)
    expected = ReadmeExamples.normalize(command.expected)
    return if expected == actual

    "README.md:#{command.line}: $ #{command.text}\n" \
      "#{GoldenHelper::Diff.unified(expected, actual, from: 'README.md', to: 'slipway')}"
  end
end
