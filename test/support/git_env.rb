# frozen_string_literal: true

require 'fileutils'
require 'open3'

# Runs git hermetically in tests: a pinned environment for fixture commands, ENV swaps for
# the production Runner, and fake git executables planted on PATH.
module GitEnv
  # No global or system configuration, a fixed clock and a fixed timezone: the same recipe
  # yields the same commit ids on every machine.
  ENVIRONMENT = {
    'GIT_CONFIG_GLOBAL' => '/dev/null', 'GIT_CONFIG_NOSYSTEM' => '1',
    'GIT_AUTHOR_DATE' => '1700000000 +0000', 'GIT_COMMITTER_DATE' => '1700000000 +0000',
    'TZ' => 'UTC', 'LC_ALL' => 'C', 'GIT_TERMINAL_PROMPT' => '0', 'GIT_OPTIONAL_LOCKS' => '0',
    'GIT_DIR' => nil, 'GIT_WORK_TREE' => nil, 'GIT_INDEX_FILE' => nil
  }.freeze

  # Identity and the switches that keep signing, hooks, global ignores and advice out.
  CONFIG = %w[
    -c user.name=Fixture -c user.email=fixture@example.com
    -c commit.gpgsign=false -c core.hooksPath=/dev/null -c core.excludesFile=/dev/null
    -c init.defaultBranch=main -c advice.detachedHead=false
  ].freeze

  # Runs git in +dir+ with the fixture environment and returns stdout; fails the test on error.
  def git!(dir, *args)
    out, err, status = git(dir, *args)
    raise "git #{args.join(' ')} failed in #{dir}: #{err}" unless status.success?

    out
  end

  # Same as git! but returns [stdout, stderr, status] and lets the caller judge the outcome.
  def git(dir, *)
    Open3.capture3(ENVIRONMENT, 'git', *CONFIG, '-C', dir, *)
  end

  # Environment that hides the developer's git configuration from the production Runner.
  def hermetic_env(root)
    { 'HOME' => root, 'XDG_CONFIG_HOME' => File.join(root, '.config'),
      'GIT_CONFIG_GLOBAL' => '/dev/null', 'GIT_CONFIG_NOSYSTEM' => '1' }
  end

  # Sets +overrides+ in ENV (nil removes a variable) and returns what to pass to restore_env.
  def replace_env(overrides)
    saved = overrides.keys.to_h { [it, ENV.fetch(it, nil)] }
    overrides.each { |key, value| ENV[key] = value }
    saved
  end

  def restore_env(saved)
    saved.each { |key, value| ENV[key] = value }
  end

  # Runs the block with +overrides+ in ENV and restores the previous values afterwards.
  def with_env(overrides)
    saved = replace_env(overrides)
    yield
  ensure
    restore_env(saved) if saved
  end

  # Writes an executable called git under +dir+/bin from +body+ (a shell script without its
  # shebang) and returns the bin directory, ready to be prepended to PATH.
  def fake_git(dir, body)
    bin = File.join(dir, 'bin')
    FileUtils.mkdir_p(bin)
    script = File.join(bin, 'git')
    File.write(script, "#!/bin/sh\n#{body}\n")
    File.chmod(0o755, script)
    bin
  end
end
