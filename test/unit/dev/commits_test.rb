# frozen_string_literal: true

require 'test_helper'
require 'rbconfig'
require 'tmpdir'
require_relative '../../../rakelib/support/commits'

class CommitsTest < Minitest::Test
  include GitEnv

  SCRIPT = File.expand_path('../../../bin/lint-commits', __dir__)
  RULE = 'subject is not a Conventional Commit ("type(scope): summary" with a lowercase summary; ' \
         "types: #{Commits::TYPES.join(', ')})".freeze
  UNFINISHED = 'subject marks a fixup, amend, squash or WIP commit'
  BOT_CO_AUTHORS = [
    'Claude Opus 5.5 <noreply@anthropic.com>', 'Cursor Agent <cursoragent@cursor.com>',
    'aider (o3) <aider@aider.chat>', 'Copilot <198982749+Copilot@users.noreply.github.com>',
    'claude[bot] <209825114+claude[bot]@users.noreply.github.com>'
  ].freeze
  HUMAN_CO_AUTHORS = [
    'Jane Doe <jane@example.com>', 'Claude Monet <claude.monet@example.com>',
    'Maria Silva <maria@teaching-assistant.edu>', 'Ana <ana@cursory.dev>'
  ].freeze
  SECURITY_SUBJECTS = ['chore(deps): [security] bump rack from 3.1.0 to 3.1.1',
                       'ci: [security] bump actions/checkout from 4 to 5'].freeze

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
    head
  end

  # git commit converts a message that is not UTF-8 from Latin-1, so the object is written by hand.
  def commit_bytes(message)
    object = "tree #{git!(@dir, 'rev-parse', 'HEAD^{tree}').strip}\nparent #{git!(@dir, 'rev-parse', 'HEAD').strip}\n" \
             "author Fixture <fixture@example.com> 1700000000 +0000\n" \
             "committer Fixture <fixture@example.com> 1700000000 +0000\n\n".b + message
    sha, err, status = Open3.capture3(GitEnv::ENVIRONMENT, 'git', '-C', @dir, 'hash-object', '-t', 'commit', '-w',
                                      '--stdin', stdin_data: object, binmode: true)
    raise err unless status.success?

    git!(@dir, 'update-ref', 'HEAD', sha.strip)
    head
  end

  def head = git!(@dir, 'rev-parse', '--short', 'HEAD').strip

  def lint(*)
    Open3.capture3(GitEnv::ENVIRONMENT, RbConfig.ruby, SCRIPT, 'main..topic', *, chdir: @dir)
  end

  def write(name, content)
    File.join(@dir, name).tap { File.binwrite(it, content) }
  end

  def co_author(identity) = "Co-Authored-By: #{identity}"

  def test_conventional_subjects_pass
    commit('feat: add the label verb')
    commit('fix(store)!: keep manifests sorted', 'Body text.', co_author(HUMAN_CO_AUTHORS.first))
    out, err, status = lint

    assert_predicate status, :success?, err
    assert_equal "lint-commits: 2 commit(s) in main..topic follow the rules\n", out
  end

  def test_every_type_is_accepted
    Commits::TYPES.each { commit("#{it}: change something") }
    out, err, status = lint

    assert_predicate status, :success?, err
    assert_equal "lint-commits: #{Commits::TYPES.size} commit(s) in main..topic follow the rules\n", out
  end

  def test_bad_subjects_are_reported_one_line_per_commit
    bad = commit('Added the label verb')
    upper = commit('feat: Add the label verb')
    unknown = commit('feature: add the label verb')
    out, _, status = lint

    assert_equal 1, status.exitstatus
    assert_equal ["#{bad} \"Added the label verb\": #{RULE}", "#{upper} \"feat: Add the label verb\": #{RULE}",
                  "#{unknown} \"feature: add the label verb\": #{RULE}"], out.lines(chomp: true)
  end

  def test_dependabot_security_updates_pass_as_subjects_and_titles
    SECURITY_SUBJECTS.each { commit(it) }
    statuses = SECURITY_SUBJECTS.map { lint('--title', write('title', "#{it}\n")).last }

    assert_equal [true, true], statuses.map(&:success?)
  end

  def test_the_security_marker_does_not_relax_the_summary_rule
    refute_empty Commits.subject_problems('chore(deps): [security] Bump rack')
    refute_empty Commits.subject_problems('chore(deps): [Security] bump rack')
  end

  def test_fixup_amend_squash_and_wip_commits_are_reported
    subjects = ['fixup! feat: add x', 'amend! feat: add x', 'squash! fix: y', 'WIP: z', 'wip', 'fix: wip',
                'chore(deps)!: WIP bump']
    shas = subjects.map { commit(it) }
    out, _, status = lint

    assert_equal 1, status.exitstatus
    assert_equal(shas, out.lines.map { it.split.first })
    assert(out.lines.all? { it.include?(UNFINISHED) })
  end

  def test_a_summary_that_starts_with_a_word_beginning_with_wip_passes
    assert_empty Commits.subject_problems('feat: wipe the cache on logout')
  end

  def test_git_revert_and_reapply_subjects_pass
    commit('fix: keep manifests sorted')
    git!(@dir, 'revert', '--no-edit', 'HEAD')
    git!(@dir, 'revert', '--no-edit', 'HEAD')
    out, err, status = lint('--title', write('title', "Revert \"fix: keep manifests sorted\"\n"))

    assert_predicate status, :success?, err
    assert_equal "lint-commits: 3 commit(s) in main..topic follow the rules\n", out
    assert_equal ['Reapply "fix: keep manifests sorted"', 'Revert "fix: keep manifests sorted"'],
                 git!(@dir, 'log', '--format=%s', '-2').lines(chomp: true)
  end

  def test_a_revert_is_held_to_the_rules_of_the_subject_it_quotes
    assert_equal [RULE.delete_prefix('subject ')], Commits.subject_problems('Revert "Added x"')
    assert_equal [UNFINISHED.delete_prefix('subject ')], Commits.subject_problems('Revert "fix: wip"')
    assert_empty Commits.subject_problems('Revert "Revert "feat: add x""')
  end

  def test_assistant_co_author_trailers_are_reported
    shas = BOT_CO_AUTHORS.map { commit('docs: note it', 'Body.', co_author(it)) }
    out, _, status = lint

    assert_equal 1, status.exitstatus
    assert_equal(shas, out.lines.map { it.split.first })
    assert_includes out, "carries an AI attribution line: \"#{co_author(BOT_CO_AUTHORS.first)}\""
  end

  def test_tool_trailers_are_reported
    lines = ['Generated-by: GitHub Copilot', 'Assisted-by: Gemini CLI',
             'Claude-Session: https://claude.ai/code/session_1', 'Generated-with: gpt-4o']
    shas = lines.map { commit('docs: note it', 'Body.', it) }
    out, _, status = lint

    assert_equal 1, status.exitstatus
    assert_equal(shas, out.lines.map { it.split.first })
  end

  def test_a_generated_with_line_is_reported
    commit('docs: explain', "\u{1f916} Generated with [Claude Code](https://example.com)")

    assert_equal 1, lint.last.exitstatus
  end

  def test_human_co_authors_and_prose_about_assistants_pass
    commit('docs: explain', *HUMAN_CO_AUTHORS.map { co_author(it) })
    commit('docs: explain the commits job', 'The job rejects lines like Generated with Claude Code.')
    commit('docs: explain', co_author('Jane Doe <jane@example.com>'), 'The docs mention the Copilot integration.')
    out, err, status = lint

    assert_predicate status, :success?, err
    assert_equal "lint-commits: 3 commit(s) in main..topic follow the rules\n", out
  end

  def test_a_clean_merge_commit_passes
    commit('feat: one')
    git!(@dir, 'switch', '--quiet', 'main')
    commit('fix: two')
    git!(@dir, 'switch', '--quiet', 'topic')
    git!(@dir, 'merge', '--quiet', '--no-edit', 'main')

    assert_predicate lint.last, :success?
  end

  def test_a_merge_commit_is_checked_for_attribution
    commit('feat: one')
    git!(@dir, 'switch', '--quiet', 'main')
    commit('fix: two')
    git!(@dir, 'switch', '--quiet', 'topic')
    git!(@dir, 'merge', '--quiet', '--no-ff', '-m', "Merge branch 'main' into topic",
         '-m', co_author(BOT_CO_AUTHORS.first), 'main')
    out, _, status = lint

    assert_equal 1, status.exitstatus
    assert_equal ["#{head} \"Merge branch 'main' into topic\": carries an AI attribution line: " \
                  "\"#{co_author(BOT_CO_AUTHORS.first)}\""], out.lines(chomp: true)
  end

  def test_non_ascii_messages_are_read_under_the_c_locale
    commit('feat: add café', 'Body.', co_author('José <jose@example.com>'))
    body = write('body', "Adds café.\n\n#{co_author('José <jose@example.com>')}\n")
    out, err, status = lint('--title', write('title', "feat: add café\n"), '--body', body)

    assert_predicate status, :success?, err
    assert_equal "lint-commits: 1 commit(s) in main..topic follow the rules\n", out
  end

  def test_bytes_that_are_not_utf8_are_replaced_instead_of_crashing
    sha = commit_bytes("Add r\xE9sum\xE9\n".b)
    out, err, status = lint('--body', write('body', "Adds a r\xE9sum\xE9.\n".b))

    assert_equal 1, status.exitstatus
    assert_equal ["#{sha} \"Add r?sum?\": #{RULE}"], out.lines(chomp: true)
    assert_empty err
  end

  def test_the_pull_request_title_and_body_are_checked
    commit('feat: add x')
    trailer = co_author(BOT_CO_AUTHORS.first)
    out, _, status = lint('--title', write('title', "Add x\n"), '--body', write('body', "Adds x.\n\n#{trailer}\n"))

    assert_equal 1, status.exitstatus
    assert_match(/\Apull request title "Add x" is not a Conventional Commit/, out.lines.first)
    assert_equal "pull request body carries an AI attribution line: \"#{trailer}\"", out.lines.last.chomp
  end

  def test_a_clean_pull_request_body_passes
    commit('feat: add x')
    body = write('body', "Adds x.\n\n#{co_author(HUMAN_CO_AUTHORS.first)}\n")

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
