# frozen_string_literal: true

require 'test_helper'

class GitUrlTest < Minitest::Test
  def test_http_and_https_lose_the_whole_userinfo
    assert_equal 'https://***@example.com/x.git', redact('https://user:secret@example.com/x.git')
    assert_equal 'https://***@example.com/x.git', redact('https://ghp_TOKEN@example.com/x.git')
    assert_equal 'http://***@example.com:8080/x', redact('http://user@example.com:8080/x')
    assert_equal 'HTTPS://***@example.com/x', redact('HTTPS://u:p@example.com/x')
  end

  def test_schemes_that_carry_http_lose_the_whole_userinfo
    assert_equal 'git+https://***@example.com/x', redact('git+https://ci:tok@example.com/x')
    assert_equal 'persistent-https://***@example.com/x', redact('persistent-https://tok@example.com/x')
    assert_equal 'hg+http://***@example.com/x', redact('hg+http://u:p@example.com/x')
    assert_equal 'Git+HTTPS://***@example.com/x', redact('Git+HTTPS://u:p@example.com/x')
  end

  def test_other_schemes_lose_only_the_password
    assert_equal 'ssh://u:***@example.com/x', redact('ssh://u:pw@example.com/x')
    assert_equal 'ftp://anon:***@example.com/pub', redact('ftp://anon:mail@example.com/pub')
    assert_equal 'git+ssh://ci:***@example.com/x', redact('git+ssh://ci:tok@example.com/x')
    assert_equal 'ssh://:***@example.com/x', redact('ssh://:pw@example.com/x')
  end

  def test_a_scheme_that_only_looks_like_http_loses_only_the_password
    assert_equal 'httpsx://u:***@example.com/x', redact('httpsx://u:p@example.com/x')
    assert_equal 'xhttps://u:***@example.com/x', redact('xhttps://u:p@example.com/x')
    assert_equal 'https+ssh://u:***@example.com/x', redact('https+ssh://u:p@example.com/x')
    assert_equal 'httpsx://tok@example.com/x', redact('httpsx://tok@example.com/x')
  end

  def test_urls_without_a_password_outside_http_are_left_alone
    ['ssh://git@example.com/x.git', 'git://example.com/x.git', 'file:///srv/x.git',
     'ssh://git@example.com:2222/x.git'].each do |url|
      assert_equal url, redact(url)
    end
  end

  def test_scp_like_addresses_and_e_mail_addresses_are_left_alone
    assert_equal 'git@github.com:hvpaiva/slipway.git', redact('git@github.com:hvpaiva/slipway.git')
    assert_equal 'Fixture <fixture@example.com>', redact('Fixture <fixture@example.com>')
    assert_equal 'mailto:me@example.com', redact('mailto:me@example.com')
  end

  def test_the_userinfo_ends_at_the_last_at_sign_of_the_authority
    assert_equal 'https://***@example.com/x', redact('https://u:p@ss@example.com/x')
    assert_equal 'ssh://u:***@example.com/x', redact('ssh://u:p@ss@example.com/x')
    assert_equal 'https://***@[::1]:8443/x', redact('https://u:p@[::1]:8443/x')
  end

  def test_an_at_sign_after_the_authority_is_not_userinfo
    assert_equal 'https://example.com/x?to=me@example.com', redact('https://example.com/x?to=me@example.com')
    assert_equal 'https://example.com#me@example.com', redact('https://example.com#me@example.com')
    assert_equal 'https://example.com me@example.com', redact('https://example.com me@example.com')
    assert_equal 'https://@example.com/x', redact('https://@example.com/x')
  end

  def test_every_url_in_free_text_is_redacted
    line = "fatal: unable to access 'https://u:s3cret@example.com/x.git/': The requested URL returned " \
           'error: 403; mirror ssh://m:pw@example.org/x.git'

    assert_equal "fatal: unable to access 'https://***@example.com/x.git/': The requested URL returned " \
                 'error: 403; mirror ssh://m:***@example.org/x.git', redact(line)
  end

  def test_redacting_twice_changes_nothing_more
    text = 'https://u:p@example.com/x ssh://u:p@example.com/y'

    assert_equal redact(text), redact(redact(text))
  end

  private

  def redact(text) = Slipway::Git::Url.redact(text)
end
