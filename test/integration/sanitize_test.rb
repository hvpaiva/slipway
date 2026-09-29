# frozen_string_literal: true

require 'test_helper'

class SanitizeIntegrationTest < Minitest::Test
  include IntegrationHelper

  URL = 'https://ci-bot:s3cret@example.com/x.git'
  LEAKS = /s3cret|ci-bot|\e/
  # Git quotes the URL it failed on. The escape sequence and the right-to-left override stand
  # in for what a server can append to that line; the second line never reaches the output.
  FAILING_GIT = <<~'SH'
    printf 'fatal: unable to access \047https://ci-bot:s3cret@example.com/x.git/\047: \033[2J\342\200\256\nremote: s3cret\n' >&2
    exit 128
  SH
  DETAIL = "git exited with status 128: fatal: unable to access 'https://***@example.com/x.git/': ^[[2J\uFFFD"

  def test_describe_redacts_the_remote_and_no_output_carries_its_credentials
    with_home do |env|
      dir = File.join(env['HOME'], 'dev', 'creds')
      build_repo(dir, 'behind')
      git!(dir, 'remote', 'set-url', 'origin', URL)
      seed(env, manifest('Project', 'creds', path: '~/dev/creds'))

      runs = [%w[describe project creds], %w[get projects], %w[get projects -o wide], %w[get projects -o json],
              %w[get projects -o yaml], %w[get projects -o name]].map { slipway(*it, env:) }

      assert_includes runs.first[1], "  Remote:      https://***@example.com/x.git\n"
      assert_equal([[0, '']] * runs.size, runs.map { |status, _, err| [status, err] })
      assert_empty(runs.map { it[1].b }.grep(LEAKS))
    end
  end

  def test_a_git_failure_is_redacted_cut_to_one_line_and_made_visible
    with_home do |env|
      seed(env, manifest('Project', 'odd', path: repo(env, 'odd')))
      bin = fake_git(File.join(env['HOME'], 'fake'), FAILING_GIT)
      env = env.merge('PATH' => "#{bin}#{File::PATH_SEPARATOR}#{env.fetch('PATH')}")

      described, described_err = outputs('describe', 'project', 'odd', env:)
      listed, listed_err = outputs('get', 'projects', env:)

      assert_includes described, "Repository:   #{DETAIL}\n".b
      assert_equal ["warning: #{DETAIL}\n".b] * 2, [described_err, listed_err]
      assert_empty([described, described_err, listed, listed_err].grep(LEAKS))
      refute_includes described + described_err, "\u202E".b
    end
  end

  private

  # Compared as bytes: the test process may run under a locale whose encoding is not UTF-8.
  def outputs(*, env:) = slipway(*, env:).drop(1).map(&:b)
end
