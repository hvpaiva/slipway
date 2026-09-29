# frozen_string_literal: true

require 'socket'
require 'test_helper'
require 'slipway/git'
require 'tmpdir'

# Every origin is a local bare repository, a fake ssh or a loopback server: nothing leaves the machine.
class GitRepositoryFetchTest < Minitest::Test
  include GitFixtures

  ZERO = '0' * 40
  # curl would send a loopback request through a proxy the developer configured.
  NO_PROXY = %w[http_proxy HTTP_PROXY https_proxy HTTPS_PROXY all_proxy ALL_PROXY].to_h { [it, nil] }.freeze

  def setup
    @root = Dir.mktmpdir('slipway-fetch-')
    @saved = replace_env(hermetic_env(@root))
    @repo = Slipway::Git::Repository.new(protocols: %w[file])
  end

  def teardown
    restore_env(@saved)
    FileUtils.remove_entry(@root)
  end

  def test_fetch_reports_the_commit_another_clone_pushed_and_status_then_sees_it
    dir = fixture('stale')

    assert_equal 0, @repo.status(dir).behind

    result = @repo.fetch(dir, prune: false)

    assert_equal 1, @repo.status(dir).behind
    skip_unless_fetch_lists_refs

    assert_equal [['refs/remotes/origin/main', head(dir), head("#{dir}-other")]], result.updates
  end

  def test_fetching_again_reports_no_updates
    skip_unless_fetch_lists_refs
    dir = fixture('stale')
    @repo.fetch(dir, prune: false)

    assert_empty @repo.fetch(dir, prune: false).updates
  end

  # Git records a fetched branch that no refspec maps in FETCH_HEAD alone, and says so on every fetch.
  def test_a_branch_tracked_outside_the_fetch_refspec_reports_no_updates
    skip_unless_fetch_lists_refs
    dir = fixture('stale')
    git!("#{dir}-other", 'push', '-q', 'origin', 'main:dev')
    single = File.join(@root, 'single')
    git!(@root, 'clone', '-q', '--single-branch', '--branch', 'main', '--', "#{dir}-origin.git", single)
    git!(single, 'checkout', '-q', '-b', 'local-dev')
    git!(single, 'config', 'branch.local-dev.remote', 'origin')
    git!(single, 'config', 'branch.local-dev.merge', 'refs/heads/dev')

    assert_empty @repo.fetch(single, prune: false).updates
    assert_empty @repo.fetch(single, prune: false).updates
  end

  def test_prune_reports_a_branch_deleted_upstream
    skip_unless_fetch_lists_refs
    dir = fixture('stale')
    other = "#{dir}-other"
    git!(other, 'push', '-q', 'origin', 'main:feature')
    @repo.fetch(dir, prune: false)
    git!(other, 'push', '-q', 'origin', '--delete', 'feature')

    assert_empty @repo.fetch(dir, prune: false).updates
    assert_equal [['refs/remotes/origin/feature', head(other), ZERO]], @repo.fetch(dir, prune: true).updates
  end

  def test_fetch_leaves_an_untracked_file_the_incoming_commit_adds_alone
    dir = fixture('stale_untracked_overlap')

    @repo.fetch(dir, prune: false)
    status = @repo.status(dir)

    assert_equal [1, 1], [status.behind, status.untracked]
    assert_equal "local b\n", File.read(File.join(dir, 'b.txt'))
  end

  def test_fetch_works_beside_a_held_index_lock_and_leaves_it_in_place
    dir = fixture('index_lock')
    result = @repo.fetch(dir, prune: false)

    assert_equal 1, @repo.status(dir).behind
    assert_path_exists File.join(dir, '.git', 'index.lock')
    skip_unless_fetch_lists_refs

    assert_equal 1, result.updates.size
  end

  def test_a_branch_that_tracks_a_local_branch_is_never_fetched
    dir = fixture('stale')
    git!(dir, 'switch', '-q', '-c', 'topic', '--track', 'main')

    error = assert_raises(Slipway::Git::LocalUpstream) { @repo.fetch(dir, prune: false) }

    assert_equal "#{dir}: the current branch tracks a local branch, not a remote one", error.message
    assert_nil @repo.fetched_at(dir)
    assert @repo.local_upstream?(dir)
    git!(dir, 'switch', '-q', 'main')

    refute @repo.local_upstream?(dir)
    assert_instance_of Slipway::Git::FetchResult, @repo.fetch(dir, prune: false)
  end

  def test_a_transport_outside_protocols_never_runs
    dir = fixture('clean')
    marker = File.join(@root, 'marker')
    git!(dir, 'remote', 'add', 'origin', "ext::sh -c touch% #{marker}")
    # Git refuses ext on its own; allowing it here leaves the refusal to the protocols setting.
    git!(dir, 'config', 'protocol.ext.allow', 'always')

    error = assert_raises(Slipway::Git::ProtocolNotAllowed) { @repo.fetch(dir, prune: false) }

    assert_equal ['ext', "#{dir}: transport 'ext' not allowed"], [error.protocol, error.message]
    assert_nil error.hint
    refute_path_exists marker
  end

  def test_file_is_refused_unless_protocols_lists_it
    dir = fixture('stale')

    error = assert_raises(Slipway::Git::ProtocolNotAllowed) { Slipway::Git::Repository.new.fetch(dir, prune: false) }

    assert_equal 'file', error.protocol
    assert_equal 'Add file to "protocols" in the configuration file to allow it.', error.hint
    assert_equal 0, @repo.status(dir).behind
  end

  def test_ssh_runs_with_the_askpass_forced_and_a_refused_key_is_auth_required
    dir = fixture('clean')
    git!(dir, 'remote', 'add', 'origin', 'ssh://example.invalid/x')
    recorded = File.join(@root, 'ssh-environment')

    with_env('GIT_SSH' => fake_ssh(recorded), 'GIT_SSH_COMMAND' => nil, 'GIT_SSH_VARIANT' => nil,
             'SSH_ASKPASS_REQUIRE' => nil) do
      error = assert_raises(Slipway::Git::AuthRequired) { Slipway::Git::Repository.new.fetch(dir, prune: false) }

      assert_equal "#{dir}: git@example.invalid: Permission denied (publickey).", error.message
      assert_equal "Run 'git -C #{dir} fetch' once in a terminal to see what git needs.", error.hint
    end
    environment = File.readlines(recorded, chomp: true)

    assert_includes environment, 'SSH_ASKPASS_REQUIRE=force'
    assert_includes environment, "SSH_ASKPASS=#{Slipway::Git::Runner::FALSE_PROGRAM}"
    assert_includes environment, 'GIT_ALLOW_PROTOCOL=ssh:https'
  end

  # Over ssh the remote writes to git's stderr unprefixed, and git either adds its own message
  # after what the remote printed or dies of SIGPIPE when the remote hangs up first.
  def test_a_refusal_the_remote_prints_is_not_a_local_refusal
    dir = ssh_origin

    ['exit 128', "exec 0<&-\nprintf 0000"].each do |tail|
      with_ssh("echo \"fatal: transport 'ext' not allowed\" >&2\n#{tail}") do
        error = assert_raises(Slipway::Git::Error) { Slipway::Git::Repository.new.fetch(dir, prune: false) }

        assert_instance_of Slipway::Git::Error, error, tail
      end
    end
  end

  def test_a_remote_that_reports_its_own_dubious_ownership_leaves_the_local_repository_trusted
    dir = ssh_origin

    with_ssh("echo \"fatal: detected dubious ownership in repository at '/srv/git/x.git'\" >&2\nexit 128") do
      error = assert_raises(Slipway::Git::Error) { Slipway::Git::Repository.new.fetch(dir, prune: false) }

      assert_instance_of Slipway::Git::Error, error
      assert_includes error.message, "fatal: detected dubious ownership in repository at '/srv/git/x.git'"
    end
  end

  def test_an_http_remote_that_answers_401_is_auth_required_at_once
    dir = fixture('clean')
    server = TCPServer.new('127.0.0.1', 0)
    thread = Thread.new { loop { unauthorized(server.accept) } }
    thread.report_on_exception = false
    git!(dir, 'remote', 'add', 'origin', "http://127.0.0.1:#{server.addr[1]}/x.git")
    repo = Slipway::Git::Repository.new(protocols: %w[http])

    with_env(NO_PROXY) do
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      assert_raises(Slipway::Git::AuthRequired) { repo.fetch(dir, prune: false) }
      assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 2
    end
  ensure
    thread&.kill&.join
    server&.close
  end

  def test_the_network_timeout_is_its_own_deadline
    dir = fixture('stale')
    bin = fake_git(@root, 'for arg; do [ "$arg" = fetch ] && exec sleep 30; done; exit 0')
    repo = Slipway::Git::Repository.new(network_timeout: 0.2, protocols: %w[file])

    with_env('PATH' => "#{bin}:#{ENV.fetch('PATH')}") do
      error = assert_raises(Slipway::Git::Timeout) { repo.fetch(dir, prune: false) }

      assert_equal "#{dir}: git did not finish within 0.2 seconds", error.message
    end
  end

  private

  def fixture(state) = build_repo(File.join(@root, state), state)

  def head(dir) = git!(dir, 'rev-parse', 'HEAD').chomp

  # Records the environment git gave it and refuses the key as a server would.
  def fake_ssh(recorded)
    ssh_script("env > #{recorded}\necho 'git@example.invalid: Permission denied (publickey).' >&2\nexit 255")
  end

  # Named ssh so git passes OpenSSH options without running it with -G first.
  def ssh_script(body)
    path = File.join(@root, 'ssh-bin', 'ssh')
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "#!/bin/sh\n#{body}\n")
    File.chmod(0o755, path)
    path
  end

  def with_ssh(body, &) = with_env('GIT_SSH' => ssh_script(body), 'GIT_SSH_COMMAND' => nil, 'GIT_SSH_VARIANT' => nil, &)

  def ssh_origin
    dir = fixture('clean')
    git!(dir, 'remote', 'add', 'origin', 'ssh://example.invalid/srv/git/x.git')
    dir
  end

  def unauthorized(client)
    nil until ["\r\n", nil].include?(client.gets)
    client.write("HTTP/1.1 401 Unauthorized\r\nWWW-Authenticate: Basic realm=\"slipway\"\r\n" \
                 "Content-Length: 0\r\nConnection: close\r\n\r\n")
  ensure
    client.close
  end
end
