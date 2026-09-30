# frozen_string_literal: true

require 'open3'
require 'test_helper'

class GitBranchNameTest < Minitest::Test
  ACCEPTED = ['main', 'a', '1', 'feature/x-1', 'release/1.2', 'v1.0_rc', 'a./b', 'user/-draft', 'x' * 255].freeze

  def test_names_in_the_grammar_are_accepted
    ACCEPTED.each { assert_equal it, Slipway::Git::BranchName.validate!(it) }
  end

  def test_every_accepted_name_is_one_git_accepts
    ACCEPTED.each do |name|
      _, status = Open3.capture2e('git', 'check-ref-format', '--branch', name)

      assert_predicate status, :success?, name
    end
  end

  def test_names_outside_the_grammar_are_refused_with_the_rule
    ['-q', '--track', '_a', '.a', '/a', 'a..b', 'a//b', 'a/.b', 'x.lock', 'a.lock/b', 'a/', 'a.', 'HEAD', 'a@{1}',
     'a~1', 'a^', 'a:b', 'a?', 'a*', 'a[b', 'a\\b', 'a b', "a\tb", "a\e[2Jb", "a\u001Bb", "a\u202Eb", "a\u00E9",
     '', 'x' * 256].each do |name|
      error = assert_raises(Slipway::Git::BranchName::Invalid, name.inspect) { Slipway::Git::BranchName.validate!(name) }

      assert_equal "#{name.inspect} is not a valid branch name: #{Slipway::Git::BranchName::RULE}", error.message
    end
  end

  def test_bytes_that_are_not_text_are_refused_without_raising
    names = [(+"a\xFF").force_encoding(Encoding::US_ASCII), (+"a\xFF").force_encoding(Encoding::UTF_8), "a\xFF".b]
    names.each do |name|
      refute Slipway::Git::BranchName.valid?(name), name.inspect
      assert_raises(Slipway::Git::BranchName::Invalid) { Slipway::Git::BranchName.validate!(name) }
    end
  end

  def test_only_strings_are_names
    [nil, 1, :main].each { refute Slipway::Git::BranchName.valid?(it) }
  end
end
