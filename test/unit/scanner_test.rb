# frozen_string_literal: true

require 'fileutils'
require 'test_helper'
require 'tmpdir'

class ScannerTest < Minitest::Test
  def test_the_children_of_the_root_that_hold_a_git_entry_are_found_in_name_order
    within do |root|
      repository(root, 'zeta')
      repository(root, 'alpha')
      FileUtils.mkdir_p(File.join(root, 'plain'))
      File.write(File.join(root, 'file.txt'), "x\n")

      assert_equal [paths(root, 'alpha', 'zeta'), []], scan(root)
    end
  end

  def test_a_root_that_is_a_repository_is_the_only_one_found
    within do |root|
      repository(root, '.')
      repository(root, 'vendor/inner')

      assert_equal [[root], []], scan(root, depth: 8)
    end
  end

  def test_a_git_file_marks_a_worktree_or_a_submodule
    within do |root|
      FileUtils.mkdir_p(File.join(root, 'worktree'))
      File.write(File.join(root, 'worktree', '.git'), "gitdir: /elsewhere/.git/worktrees/w\n")

      assert_equal [paths(root, 'worktree'), []], scan(root)
    end
  end

  def test_the_depth_bounds_the_search_and_a_repository_ends_its_branch
    within do |root|
      repository(root, 'one')
      repository(root, 'one/nested')
      repository(root, 'group/two')
      repository(root, 'group/deep/three')

      assert_equal [paths(root, 'one'), []], scan(root, depth: 1)
      assert_equal [paths(root, 'group/two', 'one'), []], scan(root, depth: 2)
      assert_equal [paths(root, 'group/deep/three', 'group/two', 'one'), []], scan(root, depth: 3)
    end
  end

  def test_a_symbolic_link_is_never_followed_below_the_root
    within do |root|
      outside = File.join(root, 'outside')
      repository(outside, 'elsewhere')
      tree = File.join(root, 'tree')
      FileUtils.mkdir_p(tree)
      File.symlink(File.join(outside, 'elsewhere'), File.join(tree, 'linked'))
      File.symlink(tree, File.join(tree, 'loop'))

      assert_equal [[], []], scan(tree, depth: 8)
    end
  end

  def test_a_root_given_as_a_symbolic_link_is_searched
    within do |root|
      repository(root, 'real/one')
      File.symlink(File.join(root, 'real'), File.join(root, 'named'))

      assert_equal [paths(root, 'named/one'), []], scan(File.join(root, 'named'))
    end
  end

  def test_an_unreadable_directory_is_reported_and_the_rest_is_still_searched
    skip 'root can read anything' if Process.uid.zero?

    within do |root|
      repository(root, 'open')
      locked = File.join(root, 'locked')
      repository(locked, 'hidden')
      File.chmod(0o000, locked)

      assert_equal [paths(root, 'open'), [Slipway::Scanner::Problem.new(path: locked, detail: 'Permission denied')]],
                   scan(root, depth: 2)
    ensure
      File.chmod(0o700, locked) if locked
    end
  end

  def test_a_root_that_is_not_a_directory_is_an_error
    within do |root|
      file = File.join(root, 'file.txt')
      File.write(file, "x\n")
      missing = File.join(root, 'missing')

      assert_equal "#{file}: no such directory", assert_raises(Slipway::Error) { scan(file) }.message
      assert_equal "#{missing}: no such directory", assert_raises(Slipway::Error) { scan(missing) }.message
    end
  end

  private

  def within(&) = Dir.mktmpdir('slipway-scan-', &)

  def repository(root, relative)
    FileUtils.mkdir_p(File.join(root, relative, '.git'))
  end

  def paths(root, *relative) = relative.map { File.join(root, it) }

  def scan(root, depth: 1)
    result = Slipway::Scanner.scan(root, depth:)
    [result.repositories, result.problems]
  end
end
