# frozen_string_literal: true

require 'tempfile'
require_relative 'changelog'
require_relative 'github'
require_relative 'runner'

class Release
  # Tests pass a clock that never sleeps.
  module SystemClock
    module_function

    def now = Time.now

    def sleep(seconds) = Kernel.sleep(seconds)
  end

  class Error < StandardError; end

  VERSION_FILE = 'lib/slipway/version.rb'
  CHANGELOG = 'CHANGELOG.md'
  VERSION_LINE = /^(?<indent>\s*VERSION = )'(?<version>[^']+)'$/
  RELEASE_VERSION = /\A\d+\.\d+\.\d+\z/
  REPOSITORY_URL = "https://github.com/#{GitHub::REPOSITORY}".freeze
  # What the release rewrites besides the two edited files: `rake generate` renders man and the
  # fixtures, and the first `bundle exec` after the version change records it in Gemfile.lock,
  # which CI installs frozen.
  GENERATED = %w[Gemfile.lock man test/fixtures/golden].freeze
  WORKFLOW = 'release.yml'
  POLL_SECONDS = 10
  POLL_ATTEMPTS = 60
  CHECK_COUNT = '.statusCheckRollup | length'

  # +runner+ takes an argv Array (and stream: true for long commands) and returns
  # [stdout, status], like CommandRunner; +clock+ answers now and sleep.
  def initialize(version, root:, runner:, clock: SystemClock, out: $stdout, **options)
    @version = version.to_s
    @root = root
    @runner = runner
    @clock = clock
    @out = out
    @dry_run = options.fetch(:dry_run, false)
    @push = options.fetch(:push, false)
    @branch = options.fetch(:branch, 'main')
    @github = options.fetch(:github) { GitHub.new(runner:, out:) }
  end

  # What rake release:verify reports; +tag+ is nil on a run from a branch. Without a tag, a
  # changelog that has not released +version+ yet is checked as bin/release would cut it on
  # +date+, so a dry run passes before the first release.
  def self.verify_problems(changelog, version, tag:, date:)
    pending = tag.nil? && Changelog.unreleased_entries(changelog) &&
              Changelog.headings(changelog).none? { it.version == version }
    changelog = Changelog.cut(changelog, version, date, REPOSITORY_URL) if pending
    problems = Changelog.release_problems(changelog, version).map { "#{CHANGELOG} has #{it}" }
    problems.unshift("tag #{tag} does not match Slipway::VERSION #{version}") if tag && tag != "v#{version}"
    problems
  end

  def tag = "v#{@version}"

  def release_branch = "release/#{tag}"

  def run
    validate
    return preview if @dry_run

    prepare
    url = open_pull_request
    @push ? publish(url) : print_next_steps(url)
    nil
  end

  private

  def validate
    validate_version
    capture(%w[git fetch origin --tags])
    validate_checkout
    validate_tag
    validate_changelog
    validate_repository
  end

  def validate_version
    raise Error, "#{@version.inspect} is not a version number" unless Gem::Version.correct?(@version)
    raise Error, "#{@version} is a prerelease; releases are X.Y.Z" if Gem::Version.new(@version).prerelease?
    raise Error, "#{@version} is not of the form X.Y.Z" unless RELEASE_VERSION.match?(@version)

    validate_order(Gem::Version.new(@version) <=> Gem::Version.new(current_version))
  end

  # The version in lib/slipway/version.rb is the one under development, so it may be released
  # as it stands until CHANGELOG.md has its heading; after that only a greater one may.
  def validate_order(comparison)
    raise Error, "#{@version} is lower than the current version #{current_version}" if comparison.negative?
    return unless comparison.zero? && Changelog.headings(changelog).any? { it.version == @version }
    raise Error, "#{@version} is already released (#{CHANGELOG} has its heading); pick a greater version" if remote_tag?

    # A tag or tag push that failed after the merge leaves the heading on the branch and the tag
    # only here, or nowhere.
    raise Error, "#{tag} is tagged locally but not pushed; run git push origin #{tag}" if local_tag?

    raise Error, "#{tag} was merged but never tagged; tag the merge commit and push the tag:\n  " \
                 "#{tag_command(release_merge_commit)}\n  git push origin #{tag}"
  end

  def release_merge_commit
    # GitHub made the merge commit, and git tag needs the object in this clone.
    capture(%w[git fetch origin --tags])
    sha = capture(['gh', 'pr', 'list', '--head', release_branch, '--base', @branch, '--state', 'merged',
                   '--json', 'mergeCommit', '--jq', '.[0].mergeCommit.oid // empty']).strip
    return sha unless sha.empty?

    raise Error, "#{CHANGELOG} has the #{@version} heading, but #{tag} exists neither locally nor on origin and no " \
                 "pull request from #{release_branch} into #{@branch} is merged; merge the release pull request " \
                 'first, or remove the heading'
  end

  def tag_command(sha) = "git tag -s #{tag} -m #{tag} #{sha}"

  def validate_checkout
    head = capture(%w[git rev-parse --abbrev-ref HEAD]).strip
    raise Error, "releases are cut from #{@branch}, but #{head} is checked out (--branch overrides)" if head != @branch

    changes = capture(%w[git status --porcelain])
    raise Error, "the working tree has uncommitted changes; commit or stash them first:\n#{changes}" if changes != ''
    return if capture(%w[git rev-parse HEAD]) == capture(['git', 'rev-parse', "origin/#{@branch}"])

    raise Error, "#{@branch} is not at origin/#{@branch}; pull or push first"
  end

  def validate_tag
    raise Error, "tag #{tag} already exists locally" if local_tag?
    raise Error, "tag #{tag} already exists on origin" if remote_tag?
  end

  def local_tag? = !capture(['git', 'tag', '--list', tag]).strip.empty?

  def remote_tag? = !capture(['git', 'ls-remote', '--tags', 'origin', "refs/tags/#{tag}"]).strip.empty?

  def validate_changelog
    @notes = Changelog.unreleased_entries(changelog)
    raise Error, "#{CHANGELOG} has no \"#{Changelog::UNRELEASED}\" heading" if @notes.nil?
    return unless @notes.empty?

    raise Error, "#{CHANGELOG} has nothing under \"#{Changelog::UNRELEASED}\"; add the release notes first"
  end

  def validate_repository
    problems = @github.release_problems
    return if problems.empty?

    raise Error, "the repository is not ready for releases:\n#{problems.map { "  - #{it}\n" }.join}" \
                 'Run bundle exec rake github:setup (safe to run again), then retry.'
  rescue GitHub::Error => e
    raise Error, "could not read the repository settings through gh: #{e.message}"
  end

  def preview
    show_diff(VERSION_FILE, new_version_file)
    show_diff(CHANGELOG, new_changelog)
    @out.puts "Dry run: #{tag} is ready to be cut; nothing was written, committed or pushed."
  end

  def show_diff(path, text)
    Tempfile.create(['release-', File.extname(path)]) do |file|
      file.write(text)
      file.flush
      out, = @runner.call(['diff', '-u', '--label', "a/#{path}", '--label', "b/#{path}", path, file.path])
      @out.print out
    end
  end

  def prepare
    step(['git', 'switch', '-c', release_branch])
    File.write(path(VERSION_FILE), new_version_file)
    File.write(path(CHANGELOG), new_changelog)
    @out.puts "wrote #{VERSION_FILE} and #{CHANGELOG}"
    step(%w[bundle exec rake generate], stream: true)
    step(%w[bundle exec rake check], stream: true, failure: "the edits stay on #{release_branch} for you to inspect")
    step(['git', 'add', '--', VERSION_FILE, CHANGELOG, *GENERATED])
    step(['git', 'commit', '-S', '-m', "chore: release #{tag}"])
    step(['git', 'push', '-u', 'origin', release_branch], stream: true)
  end

  def open_pull_request
    body = "Releases slipway #{@version}. Its tag goes on the merge commit.\n\n#{@notes}\n"
    step(['gh', 'pr', 'create', '--base', @branch, '--head', release_branch, '--title', "chore: release #{tag}",
          '--body', body]).strip.lines.last.to_s.strip
  end

  def print_next_steps(url)
    @out.puts <<~TEXT
      Opened #{url}
      Next: wait for the checks, merge, then tag the merge commit:
        gh pr checks #{url} --watch
        gh pr merge #{url} --merge --delete-branch
        git switch #{@branch} && git pull --ff-only origin #{@branch}
        git tag -s #{tag} -m #{tag}
        git push origin #{tag}
    TEXT
  end

  def publish(url)
    wait_for { capture(['gh', 'pr', 'view', url, '--json', 'statusCheckRollup', '--jq', CHECK_COUNT]).to_i.positive? }
    step(['gh', 'pr', 'checks', url, '--watch', '--fail-fast'],
         stream: true, failure: "fix the failure on #{release_branch} and push")
    step(['gh', 'pr', 'merge', url, '--merge', '--delete-branch'])
    sha = step(['gh', 'pr', 'view', url, '--json', 'mergeCommit', '--jq', '.mergeCommit.oid']).strip
    step(%w[git fetch origin --tags])
    step(['git', 'switch', @branch])
    step(['git', 'merge', '--ff-only', "origin/#{@branch}"])
    step(['git', 'tag', '-s', tag, '-m', tag, sha],
         failure: "the pull request is merged; run #{tag_command(sha)}, then git push origin #{tag}")
    step(['git', 'push', 'origin', tag],
         failure: "the pull request is merged and #{tag} is tagged locally; push it with git push origin #{tag}")
    watch_release
  end

  def watch_release
    run_id = nil
    wait_for do
      run_id = capture(['gh', 'run', 'list', '--workflow', WORKFLOW, '--branch', tag, '--event', 'push', '--limit', '1',
                        '--json', 'databaseId', '--jq', '.[0].databaseId // empty']).strip
      !run_id.empty?
    end
    failure = "#{tag} is pushed; rerun the failed jobs in Actions, or only the github-release job if the gem is " \
              'already on rubygems.org'
    step(['gh', 'run', 'watch', run_id, '--exit-status'], stream: true, failure:)
    @out.puts "Released #{tag}."
  end

  # GitHub registers checks and workflow runs a few seconds after the event that starts them.
  def wait_for
    POLL_ATTEMPTS.times do
      return if yield

      @clock.sleep(POLL_SECONDS)
    end
    raise Error, "gave up after #{POLL_ATTEMPTS * POLL_SECONDS} seconds waiting for GitHub"
  end

  def capture(argv)
    out, status = @runner.call(argv)
    raise Error, "#{argv.join(' ')} failed:\n#{out}" unless status.success?

    out
  end

  def step(argv, stream: false, failure: nil)
    @out.puts "==> #{argv.join(' ')}"
    out, status = @runner.call(argv, stream:)
    return out if status.success?

    raise Error, ["#{argv.join(' ')} failed", failure].compact.join('; ') + (out.empty? ? '' : ":\n#{out}")
  end

  def current_version
    @current_version ||= VERSION_LINE.match(File.read(path(VERSION_FILE)))&.[](:version) ||
                         raise(Error, "#{VERSION_FILE} has no VERSION = '...' line")
  end

  def new_version_file
    File.read(path(VERSION_FILE)).sub(VERSION_LINE) { "#{Regexp.last_match[:indent]}'#{@version}'" }
  end

  def new_changelog
    @new_changelog ||= Changelog.cut(changelog, @version, @clock.now.utc.strftime('%Y-%m-%d'), REPOSITORY_URL)
  end

  def changelog = File.read(path(CHANGELOG))

  def path(relative) = File.join(@root, relative)
end
