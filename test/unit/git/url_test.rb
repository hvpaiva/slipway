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

  def test_without_credentials_drops_what_redact_masks_and_the_rest_validates
    { 'https://u:s3cret@example.com/x.git' => 'https://example.com/x.git',
      'https://ghp_TOKEN@example.com/x.git' => 'https://example.com/x.git',
      'git+https://ci:tok@example.com/x' => 'git+https://example.com/x',
      'ssh://git:pw@example.com:2222/x' => 'ssh://git@example.com:2222/x',
      'ssh://git:p@ss@example.com/x' => 'ssh://git@example.com/x',
      'ssh://:pw@example.com/x' => 'ssh://example.com/x' }.each do |url, stripped|
      assert_equal stripped, Slipway::Git::Url.without_credentials(url)
      assert_equal stripped, validate(stripped) unless stripped.start_with?('git+')
    end
  end

  def test_without_credentials_leaves_other_remotes_as_they_are
    ['git@github.com:o/r.git', 'u:s3cret@host:path', 'ssh://git@host/o/r', 'https://host/o/r?to=me@example.com',
     'https://u:s3#cret@h/x'].each do |url|
      assert_equal url, Slipway::Git::Url.without_credentials(url)
    end
  end

  def test_remotes_in_the_url_and_scp_forms_are_accepted
    ['git@github.com:o/r.git', 'github.com:o/r.git', 'ssh://git@host:2222/o/r', 'ssh://host/~me/r.git',
     'https://host/o/r', 'http://host.example:8080/o/r.git', 'git://host/o/r.git', 'file:///srv/o/r.git',
     'file://localhost/srv/r.git', "file:///home/jo\u00e3o/r.git", "https://h/#{'x' * 2038}",
     'https://host:8080/o/r@v2', 'ssh://host/p:a@b'].each do |url|
      assert_equal url, validate(url)
    end
  end

  def test_remotes_outside_the_grammar_are_refused_with_the_rule
    ['ext::sh -c x', 'fd::3', 'foo::bar', '-oProxyCommand=x', 'ssh://-oProxyCommand=x/y', 'git@-oProxyCommand=x:y',
     '-x@host:y', 'host://x', 'ftp://host/x', 'HTTPS://host/x', 'git+ssh://host/x', 'ssh://[::1]/x', 'https://host',
     'host:', '/srv/r.git', '../r', '', "https://h/#{'x' * 2039}"].each do |url|
      assert_equal "#{url.inspect} is not a valid remote URL: #{Slipway::Git::Url::RULE}", refusal(url), url
    end
  end

  def test_whitespace_and_control_characters_are_refused_and_shown_escaped
    ['https://h/a b', "https://h/a\tb", "git@h:x\n", "git@h:x\e[2J", "git@h:x\u202E", "git@h:x\u200B",
     "git@h:x\u0085", "git@h:x\u00A0"].each do |url|
      assert_equal "#{url.inspect} is not a valid remote URL: #{Slipway::Git::Url::RULE}", refusal(url), url.inspect
    end
  end

  def test_credentials_are_refused_without_echoing_them
    ['https://u:s3cret@h/x', 'https://s3cret@h/x', 'git+https://s3cret@h/x', 'ssh://u:s3cret@h/x',
     'u:s3cret@host:path', "https://u:s3cret@h/x \xFF", 'u:s3/cret@host:path', 'u:s3/cr et@host:path',
     'https://u:ab/s3cret@h/x', 'https://u:s3#cret@h/x', 'https://u:s3?cret@h/x', 'https://u:s3 cret@h/x',
     "https://u:s3\ncret@h/x", 'ssh://u:s3/cret@h/x'].each do |url|
      message = refusal(url)

      assert_equal 'spec.remote must not embed credentials; use a credential helper', message, url.inspect
      refute_includes message, 's3'
    end
  end

  def test_a_refused_url_that_may_carry_a_token_is_not_quoted
    ['https://s3#cret@h/x', 'https://s3?cret@h/x', 'https://s3 cret@h/x', "https://s3\ncret@h/x",
     'git+https://s3#cret@h/x'].each do |url|
      message = refusal(url)

      assert_equal "spec.remote is not a valid remote URL: #{Slipway::Git::Url::RULE}", message, url.inspect
      refute_includes message, 's3'
    end
  end

  def test_a_user_name_outside_http_is_not_a_credential
    assert_equal 'ssh://git@host/o/r', validate('ssh://git@host/o/r')
    assert_equal 'deploy@host:o/r', validate('deploy@host:o/r')
  end

  def test_bytes_the_locale_labels_as_ascii_are_read_as_utf8
    typed = (+"file:///home/jo\xC3\xA3o/r.git").force_encoding(Encoding::US_ASCII)
    url = validate(typed)

    assert_equal ["file:///home/jo\u00e3o/r.git", Encoding::UTF_8], [url, url.encoding]
    assert_equal Encoding::US_ASCII, typed.encoding
    assert_equal "\"git@h:\uFFFD\" is not a valid remote URL: #{Slipway::Git::Url::RULE}", refusal(+"git@h:\xFF")
  end

  private

  def redact(text) = Slipway::Git::Url.redact(text)

  def validate(url) = Slipway::Git::Url.validate!(url, field: 'spec.remote')

  def refusal(url)
    assert_raises(Slipway::Git::Url::Invalid) { validate(url) }.message
  end
end
