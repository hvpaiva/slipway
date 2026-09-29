# frozen_string_literal: true

require 'test_helper'
require 'slipway/git'

# Parses porcelain v2 samples captured from git 2.55 against the fixture repositories.
class GitStatusTest < Minitest::Test
  OID = '5bbaee2c60e94db1f64d04925d8365eec25d449b'
  HEADERS = ["# branch.oid #{OID}", '# branch.head main'].freeze
  STAGED = '1 A. N... 000000 100644 100644 0000000000000000000000000000000000000000 ' \
           '587be6b4c3f93f93c489c0111bba5596147a26cb new.txt'
  UNSTAGED = '1 .M N... 100644 100644 100644 ce013625030ba8dba906f756967f9e9ca394464a ' \
             'ce013625030ba8dba906f756967f9e9ca394464a README.md'
  BOTH = '1 MM N... 100644 100644 100644 ce013625030ba8dba906f756967f9e9ca394464a ' \
         'ba2906d0666cf726c7eaadd2cd3db615dedfdf3a both.txt'
  RENAMED = '2 R. N... 100644 100644 100644 ce013625030ba8dba906f756967f9e9ca394464a ' \
            'ce013625030ba8dba906f756967f9e9ca394464a R100 README.txt'
  CONFLICT = 'u UU N... 100644 100644 100644 100644 ce013625030ba8dba906f756967f9e9ca394464a ' \
             'ba2906d0666cf726c7eaadd2cd3db615dedfdf3a e45c9c2666d44e0327c1f9c239a74c508336053e README.md'

  def test_a_clean_repository_on_a_branch
    status = parse(*HEADERS)

    assert_equal Slipway::Git::Status.new(branch: 'main', head: '5bbaee2'), status
    assert_predicate status, :clean?
    refute_predicate status, :detached?
    refute_predicate status, :unborn?
    refute_predicate status, :upstream_gone?
  end

  def test_the_head_is_abbreviated_to_seven_characters
    assert_equal '5bbaee2', parse(*HEADERS).head
  end

  def test_index_and_worktree_columns_are_counted_separately
    assert_equal [1, 0, 0], counts(parse(*HEADERS, STAGED))
    assert_equal [0, 1, 0], counts(parse(*HEADERS, UNSTAGED))
    assert_equal [0, 0, 1], counts(parse(*HEADERS, '? notes.txt'))
    assert_equal [2, 2, 1], counts(parse(*HEADERS, STAGED, UNSTAGED, BOTH, '? u.txt'))
  end

  def test_a_dirty_tree_is_not_clean
    refute_predicate parse(*HEADERS, STAGED), :clean?
    refute_predicate parse(*HEADERS, UNSTAGED), :clean?
    refute_predicate parse(*HEADERS, '? notes.txt'), :clean?
  end

  def test_a_rename_record_consumes_the_original_path_field
    status = parse(*HEADERS, RENAMED, '? old.txt', '? new.txt')

    assert_equal [1, 0, 1], counts(status)
  end

  def test_paths_may_contain_newlines_and_spaces_under_z
    status = parse(*HEADERS, '? a b.txt', "? new\nline.txt")

    assert_equal 2, status.untracked
  end

  def test_ahead_behind_and_diverged_positions
    assert_equal [1, 0], position(parse(*HEADERS, '# branch.upstream origin/main', '# branch.ab +1 -0'))
    assert_equal [0, 1], position(parse(*HEADERS, '# branch.upstream origin/main', '# branch.ab +0 -1'))
    assert_equal [1, 1], position(parse(*HEADERS, '# branch.upstream origin/main', '# branch.ab +1 -1'))
    assert_equal [0, 0], position(parse(*HEADERS, '# branch.upstream origin/main', '# branch.ab +0 -0'))
  end

  def test_a_synced_upstream_is_recorded_and_not_gone
    status = parse(*HEADERS, '# branch.upstream origin/main', '# branch.ab +0 -0')

    assert_equal 'origin/main', status.upstream
    refute_predicate status, :upstream_gone?
    assert_predicate status, :clean?
  end

  def test_an_upstream_without_a_position_line_is_gone
    status = parse("# branch.oid #{OID}", '# branch.head feature', '# branch.upstream origin/feature')

    assert_equal 'feature', status.branch
    assert_equal 'origin/feature', status.upstream
    assert_nil status.ahead
    assert_nil status.behind
    assert_predicate status, :upstream_gone?
  end

  def test_question_marks_in_the_position_mean_unknown_not_gone
    status = parse(*HEADERS, '# branch.upstream origin/main', '# branch.ab +? -?')

    assert_nil status.ahead
    assert_nil status.behind
    refute_predicate status, :upstream_gone?
  end

  def test_no_upstream_leaves_the_position_nil
    status = parse(*HEADERS)

    assert_nil status.upstream
    assert_nil status.ahead
    assert_nil status.behind
  end

  def test_detached_head
    status = parse("# branch.oid #{OID}", '# branch.head (detached)')

    assert_nil status.branch
    assert_equal '5bbaee2', status.head
    assert_predicate status, :detached?
    refute_predicate status, :unborn?
  end

  def test_unborn_branch_with_and_without_staged_files
    empty = parse('# branch.oid (initial)', '# branch.head main')
    staged = parse('# branch.oid (initial)', '# branch.head main', STAGED)

    assert_nil empty.head
    assert_equal 'main', empty.branch
    assert_predicate empty, :unborn?
    assert_predicate empty, :clean?
    assert_equal 1, staged.staged
    refute_predicate staged, :clean?
  end

  def test_conflicts_are_counted_apart_and_make_the_tree_unclean
    status = parse(*HEADERS, CONFLICT)

    assert_equal 1, status.conflicted
    assert_equal [0, 0, 0], counts(status)
    refute_predicate status, :clean?
  end

  def test_the_stash_header_is_read_and_a_stash_does_not_dirty_the_tree
    status = parse(*HEADERS, '# stash 2')

    assert_equal 2, status.stashes
    assert_predicate status, :clean?
    assert_equal 0, parse(*HEADERS).stashes
  end

  def test_ignored_entries_and_unknown_headers_are_skipped
    status = parse(*HEADERS, '# branch.future x y', '! build/', '! tmp.log')

    assert_equal Slipway::Git::Status.new(branch: 'main', head: '5bbaee2'), status
  end

  def test_empty_output_parses_to_an_empty_status
    status = Slipway::Git::Status.parse('')

    assert_nil status.branch
    assert_nil status.head
    assert_equal [0, 0, 0], counts(status)
  end

  def test_new_defaults_to_a_clean_main_branch_without_upstream
    status = Slipway::Git::Status.new(head: 'abc1234')

    assert_equal 'main', status.branch
    assert_nil status.upstream
    assert_equal [0, 0, 0], counts(status)
    assert_equal 0, status.stashes
    refute_predicate status, :upstream_gone?
  end

  private

  def parse(*records) = Slipway::Git::Status.parse("#{records.join("\0")}\0")

  def counts(status) = [status.staged, status.unstaged, status.untracked]

  def position(status) = [status.ahead, status.behind]
end

class GitCommitTest < Minitest::Test
  RECORD = "5bbaee2c60e94db1f64d04925d8365eec25d449b\u00005bbaee2\u00001700000000\u0000Fixture\u0000" \
           "fixture@example.com\u0000initial commit\u0000"

  def test_parse_reads_the_six_fields_and_a_utc_time
    commit = Slipway::Git::Commit.parse(RECORD)

    assert_equal '5bbaee2c60e94db1f64d04925d8365eec25d449b', commit.sha
    assert_equal '5bbaee2', commit.short
    assert_equal Time.utc(2023, 11, 14, 22, 13, 20), commit.time
    assert_predicate commit.time, :utc?
    assert_equal %w[Fixture fixture@example.com], [commit.author, commit.email]
    assert_equal 'initial commit', commit.subject
  end

  def test_parse_keeps_an_empty_subject_as_a_string
    commit = Slipway::Git::Commit.parse("a\u0000b\u00000\u0000c\u0000d\u0000")

    assert_equal '', commit.subject
    assert_equal Time.at(0).utc, commit.time
  end
end
