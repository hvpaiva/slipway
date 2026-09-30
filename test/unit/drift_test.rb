# frozen_string_literal: true

require 'test_helper'

class DriftTest < Minitest::Test
  def test_an_item_is_drift_unless_it_says_it_blocks
    item = Slipway::Drift::Item.new(type: 'Behind', message: '1 commit behind origin/main')

    assert_equal ['Behind', '1 commit behind origin/main', nil, false], item.to_h.values
  end

  def test_an_item_redacts_the_credentials_in_its_message_and_command
    item = Slipway::Drift::Item.new(type: 'Remote', message: 'origin is https://bot:s3cret@forge.test/x.git',
                                    command: 'git remote set-url origin ssh://git:s3cret@forge.test/x.git')

    assert_equal 'origin is https://***@forge.test/x.git', item.message
    assert_equal 'git remote set-url origin ssh://git:***@forge.test/x.git', item.command
  end

  def test_a_blocker_fills_its_fixed_sentence
    item = Slipway::Drift.blocker('Diverged', ahead: 2, behind: 5, upstream: 'origin/main', command: 'git log')

    assert_equal ['Diverged', '2 ahead, 5 behind origin/main; sync never merges or rebases', 'git log', true],
                 item.to_h.values
    assert_equal 'no commits yet; nothing to fast-forward', Slipway::Drift.blocker('Unborn').message
  end

  def test_a_word_without_a_sentence_is_a_bug
    assert_raises(KeyError) { Slipway::Drift.blocker('Busy') }
  end

  def test_blockers_and_drift_types_never_share_a_word
    assert_empty Slipway::Drift::TYPES & Slipway::Drift::BLOCKERS.keys
  end
end
