# frozen_string_literal: true

require 'fileutils'
require 'open3'
require 'rbconfig'
require 'test_helper'
require 'tmpdir'

class SandboxScriptTest < Minitest::Test
  ROOT = File.expand_path('../../..', __dir__)
  SCRIPT = File.join(ROOT, 'bin', 'sandbox')
  EXE = File.join(ROOT, 'exe', 'slipway')
  PROBE = 'printf "%s\n" "$SLIPWAY_SANDBOX" "$SLIPWAY_DATA_HOME" "$SLIPWAY_CONFIG" "$(command -v slipway)" "$HOME"'

  # realpath: on macOS the temporary directory is reached through the /var symlink, and the
  # paths the script prints are compared with these.
  def setup
    @dir = File.realpath(Dir.mktmpdir('slipway-sandbox-script-'))
    @tmp, @home, @data = %w[tmp home data].map { File.join(@dir, it) }
    FileUtils.mkdir([@tmp, @home, @data])
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  # TMPDIR puts the sandbox where the test watches it come and go. HOME and XDG_DATA_HOME stand
  # in for the user's, so a write that escapes the sandbox lands where the test looks. The Ruby
  # running the tests comes first on PATH, for the `env ruby` of exe/slipway. SHELL is set because
  # bash fills an unset one from the user database, which differs between machines.
  def sandbox(*, stdin: nil, env: {})
    path = [File.dirname(RbConfig.ruby), ENV.fetch('PATH')].join(File::PATH_SEPARATOR)
    base = { 'TMPDIR' => @tmp, 'HOME' => @home, 'XDG_DATA_HOME' => @data, 'PATH' => path, 'SHELL' => 'sh' }
    Open3.capture3(base.merge(env), SCRIPT, *, stdin_data: stdin, unsetenv_others: true)
  end

  # What PROBE prints in a sandbox at +dir+.
  def probed(dir) = [dir, File.join(dir, 'data'), File.join(dir, 'config.yaml'), EXE, @home].map { "#{it}\n" }.join

  def kept(err) = err[/^Sandbox kept: (.+)$/, 1]

  def test_a_command_runs_this_checkout_against_the_sandbox_and_the_sandbox_goes_away
    out, err, status = sandbox('sh', '-c', PROBE)

    assert_predicate status, :success?, err
    dir = out.lines(chomp: true).first

    assert_equal @tmp, File.dirname(dir)
    assert_equal probed(dir), out
    assert_empty Dir.children(@tmp)
  end

  def test_slipway_writes_its_registry_inside_the_sandbox_only
    out, err, status = sandbox('--keep', 'slipway', 'create', 'group', 'scratch')

    assert_predicate status, :success?, err
    assert_equal "group/scratch created\n", out
    assert_path_exists File.join(kept(err), 'data', 'groups', 'scratch.yaml')
    assert_empty File.read(File.join(kept(err), 'config.yaml'))
    assert_empty Dir.children(@data)
    assert_empty Dir.children(@home)
  end

  def test_without_a_command_a_subshell_runs_in_the_sandbox
    out, err, status = sandbox(stdin: PROBE)

    assert_predicate status, :success?, err
    dir = out.lines(chomp: true).first

    assert_equal probed(dir), out
    assert_equal <<~BANNER, err
      Sandbox: #{dir}, exported as SLIPWAY_SANDBOX
      slipway runs this checkout, with an empty registry and configuration.
      Leave with exit or Ctrl-D; the directory is removed then.
    BANNER
    assert_empty Dir.children(@tmp)
  end

  def test_the_subshell_is_the_shell_that_shell_names
    out, err, status = sandbox(stdin: 'printf "%s\n" "$0"')

    assert_predicate status, :success?, err
    assert_equal "sh\n", out
  end

  def test_the_subshell_is_bash_when_shell_is_empty
    out, err, status = sandbox(stdin: 'printf "%s\n" "$0"', env: { 'SHELL' => '' })

    assert_predicate status, :success?, err
    assert_equal "bash\n", out
  end

  def test_keep_leaves_the_directory_and_names_it
    _, err, status = sandbox('--keep', stdin: 'exit')
    dir = kept(err)

    assert_predicate status, :success?, err
    assert_equal <<~TEXT, err
      Sandbox: #{dir}, exported as SLIPWAY_SANDBOX
      slipway runs this checkout, with an empty registry and configuration.
      Leave with exit or Ctrl-D; the directory is kept.
      Sandbox kept: #{dir}
    TEXT
    assert_equal [File.basename(dir)], Dir.children(@tmp)
  end

  def test_home_moves_home_and_the_xdg_directories_into_the_sandbox
    probe = 'printf "%s\n" "$SLIPWAY_SANDBOX" "$HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" ' \
            '"$XDG_CACHE_HOME"'
    out, err, status = sandbox('--home', '--keep', 'sh', '-c', probe)

    assert_predicate status, :success?, err
    dir, home, *xdg = out.lines(chomp: true)

    assert_equal File.join(dir, 'home'), home
    assert_equal ['.config', '.local/share', '.local/state', '.cache'].map { File.join(home, it) }, xdg
    assert_equal(xdg, xdg.select { File.directory?(it) })
  end

  def test_the_exit_status_of_the_command_or_the_subshell_is_passed_through
    _, err, status = sandbox('sh', '-c', 'exit 3')
    _, subshell_err, subshell_status = sandbox(stdin: 'exit 4')

    assert_equal [3, ''], [status.exitstatus, err]
    assert_equal 4, subshell_status.exitstatus, subshell_err
    assert_empty Dir.children(@tmp)
  end

  def test_options_after_the_command_belong_to_it
    out, err, status = sandbox('sh', '-c', 'printf "%s" "$1"', 'sh', '--keep')

    assert_predicate status, :success?, err
    assert_equal '--keep', out
    assert_empty Dir.children(@tmp)
  end

  def test_a_double_dash_ends_the_options
    out, err, status = sandbox('--', 'sh', '-c', 'printf "%s" "$1"', 'sh', '--keep')

    assert_predicate status, :success?, err
    assert_equal '--keep', out
    assert_nil kept(err)
    assert_empty Dir.children(@tmp)
  end

  def test_help_prints_the_usage_and_creates_nothing
    out, err, status = sandbox('--help')

    assert_equal [0, ''], [status.exitstatus, err]
    assert_equal "usage: bin/sandbox [--home] [--keep] [COMMAND [ARGS...]]\n", out.lines.first
    assert_empty Dir.children(@tmp)
  end

  def test_an_unknown_option_prints_the_usage_and_creates_nothing
    help, = sandbox('-h')
    out, err, status = sandbox('--bogus')

    assert_equal [2, ''], [status.exitstatus, out]
    assert_equal "bin/sandbox: invalid option: --bogus\n#{help}", err
    assert_empty Dir.children(@tmp)
  end
end
