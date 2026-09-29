# frozen_string_literal: true

require 'test_helper'

class PlainTest < Minitest::Test
  REPLACEMENT = Slipway::Output::REPLACEMENT

  def test_control_characters_take_caret_notation
    assert_equal 'fix^[[2Jall', Slipway::Output.plain("fix\e[2Jall")
    assert_equal 'a^Ib^Jc^@d^?e', Slipway::Output.plain("a\tb\nc\0d\x7Fe")
    assert_equal '^[]0;pwned^G', Slipway::Output.plain("\e]0;pwned\a")
  end

  def test_c1_controls_become_the_replacement_character_and_text_is_scrubbed
    assert_equal "nice#{REPLACEMENT}done", Slipway::Output.plain("nice\u0085done")
    assert_equal "caf#{REPLACEMENT}", Slipway::Output.plain("caf\xFF".dup.force_encoding(Encoding::UTF_8))
  end

  def test_ordinary_text_and_non_strings_pass_through
    accented = "caf#{[0xE9].pack('U')} #{[0x2713].pack('U')}"

    assert_equal 'main', Slipway::Output.plain('main')
    assert_equal '42', Slipway::Output.plain(42)
    assert_equal '', Slipway::Output.plain(nil)
    assert_equal accented, Slipway::Output.plain(accented)
  end
end
