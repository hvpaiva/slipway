# frozen_string_literal: true

require 'test_helper'
require 'slipway/git'

class GitFetchResultTest < Minitest::Test
  OLD = 'f3675114694fe324649f24bb11276ba69f5d495f'
  NEW = 'b31879a677d13ea2124c9543cb01ad68f175b1e9'
  ZERO = '0' * 40

  def test_each_porcelain_line_becomes_ref_old_and_new
    text = "  #{OLD} #{NEW} refs/remotes/origin/main\n" \
           "* #{ZERO} #{NEW} refs/remotes/origin/feature\n" \
           "- #{OLD} #{ZERO} refs/remotes/origin/gone\n" \
           "+ #{NEW} #{OLD} refs/remotes/origin/rewritten\n" \
           "t #{OLD} #{NEW} refs/tags/v1\n"

    assert_equal [['refs/remotes/origin/main', OLD, NEW], ['refs/remotes/origin/feature', ZERO, NEW],
                  ['refs/remotes/origin/gone', OLD, ZERO], ['refs/remotes/origin/rewritten', NEW, OLD],
                  ['refs/tags/v1', OLD, NEW]],
                 Slipway::Git::FetchResult.parse(text).updates
  end

  def test_a_fetch_that_brought_nothing_has_no_updates
    assert_empty Slipway::Git::FetchResult.parse('').updates
  end

  def test_a_ref_recorded_only_in_fetch_head_is_not_an_update
    text = "* #{ZERO} #{NEW} FETCH_HEAD\n  #{OLD} #{NEW} refs/remotes/origin/main\n"

    assert_equal [['refs/remotes/origin/main', OLD, NEW]], Slipway::Git::FetchResult.parse(text).updates
  end

  def test_the_result_is_frozen_all_the_way_down
    result = Slipway::Git::FetchResult.parse("  #{OLD} #{NEW} refs/remotes/origin/main\n")

    assert_predicate result, :frozen?
    assert_predicate result.updates, :frozen?
    assert_predicate result.updates.first, :frozen?
  end
end
