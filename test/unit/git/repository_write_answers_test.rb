# frozen_string_literal: true

require 'test_helper'
require 'slipway/git'
require 'tmpdir'

# Repository#fast_forward against canned git answers: the argv it builds and what each refusal means.
class GitRepositoryWriteAnswersTest < Minitest::Test
  FROM = 'a' * 40
  TO = 'b' * 40
  MERGE = %w[-c gc.auto=0 -c maintenance.auto=false -c transfer.bundleURI=false
             merge --ff-only --no-stat --quiet --no-autostash --no-overwrite-ignore].freeze

  STATUS = ["# branch.oid #{FROM}", '# branch.head main', '# branch.upstream origin/main', '# branch.ab +0 -2']
           .map { "#{it}\0" }.join.freeze
  READS = %w[status rev-parse rev-list merge-base].freeze
  # What git prints under LC_ALL=C for each refusal, and the error it becomes.
  REFUSED = {
    "error: Unable to create '/srv/x/.git/index.lock': File exists.\n\nAnother git process seems to be " \
    "running in this repository\n" => Slipway::Git::Busy,
    "fatal: Unable to create '/srv/x/.git/index.lock': File exists.\n" => Slipway::Git::Busy,
    "error: The following untracked working tree files would be overwritten by merge:\n\tb.txt\n" \
    "Please move or remove them before you merge.\nAborting\n" => Slipway::Git::WouldOverwrite,
    "error: The following untracked working tree files would be removed by merge:\n\tb/x\n" =>
      Slipway::Git::WouldOverwrite,
    "error: Updating the following directories would lose untracked files in them:\n\tb\n\nAborting\n" =>
      Slipway::Git::WouldOverwrite,
    "error: Your local changes to the following files would be overwritten by merge:\n\tREADME.md\n" =>
      Slipway::Git::WouldLoseChanges,
    "error: Entry 'README.md' not uptodate. Cannot merge.\n" => Slipway::Git::WouldLoseChanges,
    "hint: Diverging branches can't be fast-forwarded, you need to either:\nhint:\n" \
    "fatal: Not possible to fast-forward, aborting.\n" => Slipway::Git::NotFastForward
  }.freeze

  # Answers a clean branch two commits behind origin/main, with no ref of an operation in
  # progress. Each command takes the answer of the first key among its arguments, so --verify is
  # looked up before rev-parse; --git-path names each path inside .git.
  class CannedRunner
    ANSWERS = {
      'status' => { out: STATUS },
      '--verify' => { status: 1 },
      'rev-parse' => { out: "#{FROM}\n#{TO}\n" },
      'rev-list' => { out: "0\t2\n" },
      'merge' => {},
      'merge-base' => {}
    }.freeze

    attr_reader :calls

    def initialize(**answers)
      @answers = ANSWERS.merge(answers).transform_values do |fields|
        Slipway::Git::Runner::Result.new(status: 0, out: '', err: '', **fields)
      end
      @calls = []
    end

    def run(_path, *args, **options)
      @calls << [*args, options]
      return git_paths(args) if args.include?('--git-path')

      @answers.fetch(@answers.keys.find { args.include?(it) })
    end

    private

    def git_paths(args)
      out = args.each_cons(2).filter_map { |flag, name| ".git/#{name}\n" if flag == '--git-path' }.join
      Slipway::Git::Runner::Result.new(status: 0, out:, err: '')
    end
  end

  def setup
    @root = Dir.mktmpdir('slipway-write-answers-')
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def test_only_the_merge_runs_with_the_network_profile_and_the_reflog_action
    runner = CannedRunner.new
    repo = Slipway::Git::Repository.new(runner:, network_timeout: 7, protocols: %w[ssh])

    assert_equal Slipway::Git::FastForward.new(from: FROM, to: TO, count: 2), repo.fast_forward(@root)
    repo.fast_forward(@root, reflog_action: 'slipway rollout undo')

    reads, merges = runner.calls.partition { it.intersect?(READS) }
    environment = Slipway::Git::Runner.network_environment(%w[ssh])

    assert_equal [{}], reads.map(&:last).uniq
    assert_equal [[*MERGE, TO, { timeout: 7, env: environment.merge('GIT_REFLOG_ACTION' => 'slipway sync') }],
                  [*MERGE, TO, { timeout: 7, env: environment.merge('GIT_REFLOG_ACTION' => 'slipway rollout undo') }]],
                 merges
  end

  def test_the_upstream_is_read_as_a_commit_and_so_is_a_given_object_name
    runner = CannedRunner.new
    repo = Slipway::Git::Repository.new(runner:)
    long = 'c' * 64

    repo.fast_forward(@root)
    repo.fast_forward(@root, onto: TO)
    repo.fast_forward(@root, onto: long)

    resolved = runner.calls.filter_map { it[0..-2] if it[0] == 'rev-parse' && it[1] == 'HEAD' }

    assert_equal [%w[rev-parse HEAD @{upstream}^{commit}], ['rev-parse', 'HEAD', "#{TO}^{commit}"],
                  ['rev-parse', 'HEAD', "#{long}^{commit}"]], resolved
  end

  def test_nothing_but_the_upstream_or_a_full_lowercase_object_name_reaches_git
    runner = CannedRunner.new
    repo = Slipway::Git::Repository.new(runner:)

    ['abc1234', 'A' * 40, "#{'a' * 40}\n", 'a' * 41, '-x', 'HEAD', 'origin/main', '@{u}'].each do |onto|
      error = assert_raises(ArgumentError, onto) { repo.fast_forward(@root, onto:) }

      assert_equal "onto must be @{upstream} or a full object name, not #{onto.inspect}", error.message
    end
    assert_empty runner.calls
  end

  def test_each_refusal_git_prints_becomes_its_own_error
    REFUSED.each do |err, klass|
      error = assert_raises(klass) { refused(err) }

      assert_equal [@root, klass.name.split('::').last], [error.path, error.reason]
    end
  end

  def test_any_other_merge_failure_is_classified_as_a_network_command
    unsigned = assert_raises(Slipway::Git::Error) { refused("fatal: Commit bbbbbbb does not have a GPG signature.\n") }

    assert_instance_of Slipway::Git::Error, unsigned
    assert_equal "#{@root}: git exited with status 128: fatal: Commit bbbbbbb does not have a GPG signature.",
                 unsigned.message
    assert_raises(Slipway::Git::AuthRequired) do
      refused("fatal: could not read Username for 'https://example.com': terminal prompts disabled\n")
    end
  end

  # An upstream that vanished after the checks, or an object git cannot read, is a plain failure.
  def test_only_an_object_name_git_does_not_know_is_revision_not_found
    unknown = { status: 128, err: "fatal: ambiguous argument 'x': unknown revision or path not in the working tree.\n" }
    corrupt = { status: 128, err: "fatal: bad object #{TO}\n" }
    [[Slipway::Git::Repository::UPSTREAM, unknown], [TO, corrupt]].each do |onto, answer|
      repo = Slipway::Git::Repository.new(runner: CannedRunner.new('rev-parse' => answer))

      assert_instance_of Slipway::Git::Error, assert_raises(Slipway::Git::Error) { repo.fast_forward(@root, onto:) }
    end
    repo = Slipway::Git::Repository.new(runner: CannedRunner.new('rev-parse' => unknown))

    assert_equal 'RevisionNotFound', assert_raises(Slipway::Git::Blocked) { repo.fast_forward(@root, onto: TO) }.reason
  end

  def test_the_detail_counts_every_unmerged_path_and_every_change
    { ['u UU a.txt', 'u UU b.txt'] => ['Conflicted', '2 unmerged paths'],
      ['1 M. a.txt', '1 A. b.txt', '1 MM c.txt'] => ['Dirty', '3 staged, 1 unstaged'] }.each do |records, expected|
      status = STATUS + records.map { "#{it}\0" }.join
      repo = Slipway::Git::Repository.new(runner: CannedRunner.new('status' => { out: status }))
      error = assert_raises(Slipway::Git::Blocked) { repo.fast_forward(@root) }

      assert_equal expected, [error.reason, error.message.delete_prefix("#{@root}: ")]
    end
  end

  def test_in_progress_reads_the_paths_git_names_against_the_repository
    repo = Slipway::Git::Repository.new(runner: CannedRunner.new)
    FileUtils.mkdir_p(File.join(@root, '.git', 'sequencer'))

    assert_nil repo.in_progress(@root)
    FileUtils.touch(File.join(@root, '.git', 'BISECT_LOG'))

    assert_equal 'bisect', repo.in_progress(@root)
  end

  def test_a_sequence_is_named_by_its_first_command
    repo = Slipway::Git::Repository.new(runner: CannedRunner.new)
    FileUtils.mkdir_p(File.join(@root, '.git', 'sequencer'))
    { "revert 1234567 \xFF subject\n" => 'revert', "\n pick 1234567 subject\n" => 'cherry-pick',
      "p 1234567 subject\n" => 'cherry-pick', '' => 'cherry-pick' }.each do |todo, operation|
      File.binwrite(File.join(@root, '.git', 'sequencer', 'todo'), todo)

      assert_equal operation, repo.in_progress(@root), todo
    end
  end

  private

  def refused(err)
    Slipway::Git::Repository.new(runner: CannedRunner.new('merge' => { status: 128, err: })).fast_forward(@root)
  end
end
