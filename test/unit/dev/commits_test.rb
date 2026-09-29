# frozen_string_literal: true

require 'test_helper'
require 'rbconfig'
require 'tmpdir'
require_relative '../../../rakelib/support/commits'

# bin/lint-commits and the rules behind it, run against throwaway git repositories.
class CommitsTest < Minitest::Test
  include GitEnv

  SCRIPT = File.expand_path('../../../bin/lint-commits', __dir__)
  # Assembled from parts, as a contributor's tool would write them.
  ASSISTANTS = %w[Claude Copilot Cursor].freeze

  def setup
    @dir = Dir.mktmpdir('slipway-commits-')
    git!(@dir, 'init', '--quiet')
    commit('chore: start')
    git!(@dir, 'switch', '--quiet', '-c', 'topic')
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  # Each commit adds its own file, so branches merge without conflicts.
  def commit(*paragraphs)
    @files = @files.to_i + 1
    name = "file-#{@files}.txt"
    File.write(File.join(@dir, name), paragraphs.join)
    git!(@dir, 'add', name)
    git!(@dir, 'commit', '--quiet', *paragraphs.flat_map { ['-m', it] })
    git!(@dir, 'rev-parse', '--short', 'HEAD').strip
  end

  def lint(*)
    Open3.capture3(GitEnv::ENVIRONMENT, RbConfig.ruby, SCRIPT, 'main..topic', *, chdir: @dir)
  end

  def trailer(name) = "Co-Authored-By: #{name} <noreply@example.com>"

  def test_conventional_subjects_pass
    commit('feat: add the label verb')
    commit('fix(store)!: keep manifests sorted', "Body text.\n\n#{trailer('Jane Doe')}")
    out, err, status = lint

    assert_predicate status, :success?, err
    assert_equal "lint-commits: 2 commit(s) in main..topic follow the rules\n", out
  end

  def test_every_type_is_accepted
    Commits::TYPES.each { commit("#{it}: change something") }

    assert_empty Commits.lint(Commits.read('main..topic', chdir: @dir))
  end

  def test_bad_subjects_are_reported_one_line_per_commit
    bad = commit('Added the label verb')
    upper = commit('feat: Add the label verb')
    unknown = commit('feature: add the label verb')
    out, _, status = lint
    rule = 'subject is not a Conventional Commit ("type(scope): summary" with a lowercase summary; ' \
           "types: #{Commits::TYPES.join(', ')})"

    assert_equal 1, status.exitstatus
    assert_equal ["#{bad} \"Added the label verb\": #{rule}", "#{upper} \"feat: Add the label verb\": #{rule}",
                  "#{unknown} \"feature: add the label verb\": #{rule}"], out.lines(chomp: true)
  end

  def test_fixup_squash_and_wip_commits_are_reported
    shas = ['fixup! feat: add x', 'squash! fix: y', 'WIP: z', 'wip'].map { commit(it) }
    out, _, status = lint

    assert_equal 1, status.exitstatus
    assert_equal(shas, out.lines.map { it.split.first })
    assert(out.lines.all? { it.include?('subject marks a fixup, squash or WIP commit') })
  end

  def test_attribution_trailers_in_bodies_are_reported
    shas = ASSISTANTS.map { commit("docs: note #{it}", "Body.\n\n#{trailer("#{it} Bot")}") }
    out, _, status = lint

    assert_equal 1, status.exitstatus
    assert_equal(shas, out.lines.map { it.split.first })
    assert_includes out, "carries an AI attribution line: \"#{trailer('Claude Bot')}\""
  end

  def test_a_generated_with_line_is_reported
    commit('docs: explain', "Generated with [#{ASSISTANTS.first} Code](https://example.com)")

    assert_equal 1, lint.last.exitstatus
  end

  def test_a_human_co_author_is_allowed_even_when_a_later_line_names_an_assistant
    commit('docs: explain', "#{trailer('Jane Doe')}\n\nThe docs mention the Copilot integration.")

    assert_predicate lint.last, :success?
  end

  def test_merge_commits_are_skipped
    commit('feat: one')
    git!(@dir, 'switch', '--quiet', 'main')
    commit('fix: two')
    git!(@dir, 'switch', '--quiet', 'topic')
    git!(@dir, 'merge', '--quiet', '--no-edit', 'main')

    assert_predicate lint.last, :success?
  end

  def test_the_pull_request_title_and_body_are_checked
    commit('feat: add x')
    title = File.join(@dir, 'title')
    body = File.join(@dir, 'body')
    File.write(title, "Add x\n")
    File.write(body, "Adds x.\n\n#{trailer(ASSISTANTS.first)}\n")
    out, _, status = lint('--title', title, '--body', body)

    assert_equal 1, status.exitstatus
    assert_match(/\Apull request title "Add x" is not a Conventional Commit/, out.lines.first)
    assert_equal "pull request body carries an AI attribution line: \"#{trailer(ASSISTANTS.first)}\"",
                 out.lines.last.chomp
  end

  def test_a_clean_pull_request_body_passes
    commit('feat: add x')
    body = File.join(@dir, 'body')
    File.write(body, "Adds x.\n\n#{trailer('Jane Doe')}\n")

    assert_predicate lint('--body', body).last, :success?
  end

  def test_usage_and_git_errors_exit_with_status_two
    _, err, status = Open3.capture3(GitEnv::ENVIRONMENT, RbConfig.ruby, SCRIPT, chdir: @dir)

    assert_equal 2, status.exitstatus
    assert_equal "lint-commits: invalid argument: exactly one RANGE is required\n", err

    _, err, status = Open3.capture3(GitEnv::ENVIRONMENT, RbConfig.ruby, SCRIPT, 'nothing..here', chdir: @dir)

    assert_equal 2, status.exitstatus
    assert_match(/\Alint-commits: git log nothing\.\.here failed: /, err)
  end
end
