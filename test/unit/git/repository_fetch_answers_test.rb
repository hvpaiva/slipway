# frozen_string_literal: true

require 'test_helper'
require 'slipway/git'
require 'tmpdir'

# Repository#fetch against canned git answers: the argv it builds and what each answer means.
class GitRepositoryFetchAnswersTest < Minitest::Test
  # Each run takes the next answer, and the last one repeats. The upstream check before a fetch
  # is answered apart, so the answers and the calls cover the fetch alone.
  class CannedRunner
    UPSTREAM = Slipway::Git::Runner::Result.new(status: 0, out: "*origin\n", err: '')

    attr_reader :calls

    def initialize(*answers, **answer)
      @results = (answers.empty? ? [answer] : answers).map do |fields|
        Slipway::Git::Runner::Result.new(status: 0, out: '', err: '', **fields)
      end
      @calls = []
    end

    def run(*args, **options)
      return UPSTREAM if args.include?('for-each-ref')

      @calls << [*args, options]
      @results.size > 1 ? @results.shift : @results.first
    end
  end

  def setup
    @root = Dir.mktmpdir('slipway-fetch-answers-')
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def test_fetch_prefixes_the_network_configuration_and_passes_its_timeout_and_environment
    runner = CannedRunner.new
    repo = Slipway::Git::Repository.new(runner:, network_timeout: 7, protocols: %w[ssh https])

    repo.fetch(@root, prune: true)
    repo.fetch(@root, prune: false)

    network = %w[-c gc.auto=0 -c maintenance.auto=false -c transfer.bundleURI=false fetch --porcelain --no-all
                 --atomic --no-recurse-submodules --no-auto-maintenance]
    options = { timeout: 7, env: Slipway::Git::Runner.network_environment(%w[ssh https]) }

    assert_equal [[@root, *network, '--prune', options], [@root, *network, options]], runner.calls
  end

  def test_a_git_without_fetch_porcelain_fetches_without_it_from_then_on
    usage = { status: 129, err: "error: unknown option `porcelain'\nusage: git fetch [<options>] [<repository>]\n" }
    runner = CannedRunner.new(usage, {})
    repo = Slipway::Git::Repository.new(runner:)

    assert_nil repo.fetch(@root, prune: false).updates
    assert_nil repo.fetch(@root, prune: true).updates

    porcelain = runner.calls.map { it.include?('--porcelain') }

    assert_equal [true, false, false], porcelain
    assert_equal %w[--no-all --atomic --no-recurse-submodules --no-auto-maintenance --prune], runner.calls.last[-6..-2]
  end

  def test_a_git_without_fetch_porcelain_still_names_a_refused_transport
    runner = CannedRunner.new({ status: 129, err: "error: unknown option `porcelain'\n" },
                              { status: 128, err: "fatal: transport 'file' not allowed\n" })

    error = assert_raises(Slipway::Git::ProtocolNotAllowed) do
      Slipway::Git::Repository.new(runner:).fetch(@root, prune: false)
    end

    assert_equal 'file', error.protocol
  end

  def test_a_refused_transport_names_where_the_protocols_are_listed
    refusal = { status: 128, err: "fatal: transport 'file' not allowed\n" }
    hints = [{}, { protocols_source: 'SLIPWAY_PROTOCOLS' }].map do |source|
      repo = Slipway::Git::Repository.new(runner: CannedRunner.new(**refusal), **source)
      assert_raises(Slipway::Git::ProtocolNotAllowed) { repo.fetch(@root, prune: false) }.hint
    end

    assert_equal ['Add file to "protocols" in the configuration file to allow it.',
                  'Add file to SLIPWAY_PROTOCOLS to allow it.'], hints
  end

  def test_git_and_remote_phrases_that_mean_a_missing_or_refused_credential
    [
      "fatal: could not read Username for 'https://example.com': terminal prompts disabled\n",
      "error: unable to read askpass response from '/usr/bin/false'\nfatal: could not read Password for 'x'\n",
      "remote: Invalid username or password.\nfatal: Authentication failed for 'https://example.com/x/'\n",
      "Host key verification failed.\nfatal: Could not read from remote repository.\n",
      "fatal: unable to access 'https://example.com/x/': The requested URL returned error: 403\n"
    ].each do |stderr|
      repo = Slipway::Git::Repository.new(runner: CannedRunner.new(status: 128, err: stderr))

      assert_raises(Slipway::Git::AuthRequired, stderr) { repo.fetch(@root, prune: false) }
    end
  end

  def test_a_refused_transport_that_is_not_a_valid_protocol_name_stays_a_plain_error
    runner = CannedRunner.new(status: 128, err: "fatal: transport 'X:y' not allowed\n")
    repo = Slipway::Git::Repository.new(runner:)

    error = assert_raises(Slipway::Git::Error) { repo.fetch(@root, prune: false) }

    assert_instance_of Slipway::Git::Error, error
  end

  def test_any_other_fetch_failure_keeps_the_first_stderr_line_redacted_and_cut
    url = "https://ci-bot:s3cret@example.com/#{'x' * 180}.git"
    stderr = "fatal: unable to access '#{url}/': Could not resolve host: example.com\nremote: s3cret\n"
    repo = Slipway::Git::Repository.new(runner: CannedRunner.new(status: 128, err: stderr))

    error = assert_raises(Slipway::Git::Error) { repo.fetch(@root, prune: false) }
    kept = error.message.delete_prefix("#{@root}: git exited with status 128: ")

    assert_instance_of Slipway::Git::Error, error
    assert_equal "fatal: unable to access 'https://***@example.com/#{'x' * 180}.git/'"[0, 200], kept
    refute_includes error.message, 's3cret'
  end

  # Git refuses a transport before it connects, so its refusal is all of stderr and ends in die().
  def test_a_refusal_line_among_other_output_or_ended_by_a_signal_stays_a_plain_error
    refusal = "fatal: transport 'ext' not allowed\n"
    [[128, "Welcome\n#{refusal}"], [128, "#{refusal}fatal: Could not read from remote repository.\n"],
     [141, refusal]].each do |status, err|
      repo = Slipway::Git::Repository.new(runner: CannedRunner.new(status:, err:))
      error = assert_raises(Slipway::Git::Error) { repo.fetch(@root, prune: false) }

      assert_instance_of Slipway::Git::Error, error, err
    end
  end
end
