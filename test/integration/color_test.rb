# frozen_string_literal: true

require 'test_helper'
require 'pty'

class ColorIntegrationTest < Minitest::Test
  include IntegrationHelper

  HEADER = "\e[1mNAME    BRANCH   STATUS     AGE\e[0m"
  # The AGE cell is painted too, so it is the one cell matched loosely.
  CLEAN_ROW = /\A\e\[37mclean\e\[0m   \e\[36mmain\e\[0m     \e\[32mClean\e\[0m      \e\[36m#{DURATION}\e\[0m\z/
  PLAIN_ROW = /\A\e\[37mplain\e\[0m   \e\[90;3m<none>\e\[0m   \e\[31mNotARepo\e\[0m   \e\[36m#{DURATION}\e\[0m\z/
  LIGHT_ROW = /\A\e\[30mclean\e\[0m   \e\[34mmain\e\[0m     \e\[32mClean\e\[0m      \e\[34m#{DURATION}\e\[0m\z/
  PLAIN = "NAME    BRANCH   STATUS     AGE\n"

  def two(env)
    seed(env, manifest('Project', 'clean', path: repo(env, 'clean')),
         manifest('Project', 'plain', path: repo(env, 'plain', 'plain_dir')))
  end

  def assert_colored(out)
    header, clean, plain = out.lines(chomp: true)

    assert_equal HEADER, header
    assert_match CLEAN_ROW, clean
    assert_match PLAIN_ROW, plain
  end

  def test_always_paints_the_header_bold_and_the_status_word_by_state
    with_home do |env|
      two(env)
      status, out, err = slipway('get', 'projects', '--color=always', env:)

      assert_equal [0, ''], [status, err]
      assert_colored(out)
      assert_colored(slipway!('get', 'projects', '--color', env:))
      assert_colored(slipway!('--color=always', 'get', 'projects', env:))
    end
  end

  def test_auto_stays_plain_on_a_pipe_and_force_color_turns_it_on
    with_home do |env|
      two(env)
      env = env.merge('TERM' => 'xterm')

      assert_equal PLAIN, slipway!('get', 'projects', env:).lines.first
      assert_colored(slipway!('get', 'projects', env: env.merge('FORCE_COLOR' => '1')))
      assert_colored(slipway!('get', 'projects', env: env.merge('CLICOLOR_FORCE' => '1')))
      assert_equal PLAIN, slipway!('get', 'projects', env: env.merge('FORCE_COLOR' => '')).lines.first
    end
  end

  def test_no_color_beats_force_color_but_not_an_explicit_always
    with_home do |env|
      two(env)
      env = env.merge('TERM' => 'xterm', 'NO_COLOR' => '1')

      assert_equal PLAIN, slipway!('get', 'projects', env: env.merge('FORCE_COLOR' => '1')).lines.first
      assert_colored(slipway!('get', 'projects', '--color=always', env:))
      assert_colored(slipway!('get', 'projects', env: env.merge('SLIPWAY_COLOR' => 'always')))
    end
  end

  def test_the_variable_and_the_file_set_the_default_mode_and_a_flag_outranks_both
    with_home do |env|
      two(env)
      write_config(env, "color: always\n")

      assert_colored(slipway!('get', 'projects', env:))
      assert_equal PLAIN, slipway!('get', 'projects', env: env.merge('SLIPWAY_COLOR' => 'never')).lines.first
      assert_equal PLAIN, slipway!('get', 'projects', '--color=never', env: env.merge('SLIPWAY_COLOR' => 'always'))
        .lines.first
    end
  end

  def test_the_light_theme_swaps_the_column_colors
    with_home do |env|
      two(env)
      _, out, = slipway('get', 'projects', '--color=always', env: env.merge('SLIPWAY_THEME' => 'light'))

      assert_equal HEADER, out.lines.first.chomp
      assert_match LIGHT_ROW, out.lines[1].chomp

      write_config(env, "theme: light\n")

      assert_match LIGHT_ROW, slipway!('get', 'projects', '--color=always', env:).lines[1].chomp
    end
  end

  def test_stderr_is_painted_on_its_own
    with_home do |env|
      two(env)
      _, _, always = slipway('get', 'project', 'nothere', '--color=always', env:)
      _, _, auto = slipway('get', 'project', 'nothere', env: env.merge('TERM' => 'xterm'))

      assert_equal "\e[31merror:\e[0m projects \"nothere\" not found\n", always
      assert_equal "error: projects \"nothere\" not found\n", auto
      assert_equal "project/clean \e[32mlabeled\e[0m \e[36m(dry run)\e[0m\n",
                   slipway!('label', 'project', 'clean', 'a=b', '--color=always', '--dry-run=client', env:)
    end
  end

  def test_auto_mode_paints_when_stdout_is_a_terminal
    with_home do |env|
      two(env)
      out = in_terminal(env.merge('TERM' => 'xterm'), 'get', 'projects')

      assert_colored(out.gsub("\r\n", "\n"))
      assert_equal PLAIN, in_terminal(env.merge('TERM' => 'xterm', 'NO_COLOR' => '1'), 'get', 'projects')
        .gsub("\r\n", "\n").lines.first
    end
  end

  private

  # Runs the command with a pseudo-terminal as its stdout and returns everything it wrote.
  def in_terminal(env, *)
    reader, writer, pid = PTY.spawn(env, *COMMAND, *, unsetenv_others: true)
    writer.close
    out = +''
    begin
      loop { out << reader.readpartial(4096) }
    rescue EOFError, Errno::EIO
      reader.close
    end
    Process.wait(pid)
    out
  end
end
