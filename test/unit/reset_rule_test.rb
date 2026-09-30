# frozen_string_literal: true

require 'prism'
require 'test_helper'

# Git's reset is forbidden but for the one form rollout undo moves a branch back with. The rule
# reads syntax trees, so a word in a comment or a help sentence never counts.
class ResetRuleTest < Minitest::Test
  LIB = File.expand_path('../../lib/slipway', __dir__)

  def test_the_only_reset_argument_is_the_keep_form
    assert_equal(['git/rolling_back.rb'], files_where { it.is_a?(Prism::StringNode) && it.unescaped == 'reset' })
    assert_equal %w[reset --keep --quiet --no-recurse-submodules], Slipway::Git::Repository::RESET_ARGS
  end

  def test_only_the_rollback_moves_a_branch_back
    assert_equal(['rollback.rb'], files_where { it.is_a?(Prism::CallNode) && it.name == :roll_back && it.receiver })
  end

  private

  def files_where(&)
    Dir.glob('**/*.rb', base: LIB).sort.select { nodes(Prism.parse_file(File.join(LIB, it)).value).any?(&) }
  end

  def nodes(node) = [node, *node.compact_child_nodes.flat_map { nodes(it) }]
end
