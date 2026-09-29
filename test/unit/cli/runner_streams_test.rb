# frozen_string_literal: true

require 'test_helper'

class RunnerStreamsTest < Minitest::Test
  class BrokenPipe < StringIO
    def write(*) = raise(Errno::EPIPE)
  end

  def setup
    @fixture = FixtureRegistry.new
  end

  def test_broken_pipe_raised_by_a_handler_exits_zero_silently
    @fixture.failure = Errno::EPIPE
    status, out, err = @fixture.run('get', 'projects')

    assert_equal [0, '', ''], [status, out, err]
  end

  def test_broken_pipe_while_reporting_an_error_keeps_the_exit_status
    @fixture.failure = Slipway::Error.new('boom')
    context = Slipway::CLI::Context.new(out: StringIO.new, err: BrokenPipe.new)

    assert_equal 1, Slipway::CLI::Runner.new(@fixture.registry, context).run(%w[get projects])
    assert_equal 2, Slipway::CLI::Runner.new(@fixture.registry, context).run(%w[get --bogus])
  end

  def test_broken_stdout_lets_the_handler_finish_and_exits_zero
    context = Slipway::CLI::Context.new(out: BrokenPipe.new, err: StringIO.new)
    handler = @fixture.registry.resolve(%w[get]).first.handler
    handler.define_singleton_method(:call) do |ctx, _args, _opts|
      ctx.puts('first')
      ctx.puts('second')
    end

    assert_equal 0, Slipway::CLI::Runner.new(@fixture.registry, context).run(%w[get projects])
    assert_empty context.err.string
  end

  def test_color_flag_paints_an_error_raised_before_the_parse_reaches_it
    _, _, flag_first = @fixture.run('get', '--bogus', '--color=always')
    _, _, bad_command = @fixture.run('gett', '--color=always')

    assert_equal "\e[31merror:\e[0m unknown flag: --bogus\nSee 'slipway get --help' for usage.\n", flag_first
    assert_match(/\A\e\[31merror:\e\[0m unknown command "gett"/, bad_command)
  end
end
