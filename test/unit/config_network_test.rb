# frozen_string_literal: true

require 'test_helper'

class ConfigNetworkTest < Minitest::Test
  include ConfigHelper

  PROTOCOLS = 'must be a list of lowercase git transport names, such as ssh, https or file'
  PROTOCOLS_VARIABLE = 'must be lowercase git transport names separated by colons, such as ssh:https'
  EXT = 'must not include ext, which runs a command named in the URL'
  FD = 'must not include fd, which reads from file descriptors'

  def test_network_keys_come_from_the_file
    with_sandbox do |env|
      write(env, "networkTimeout: 5\nprotocols: [ssh, https, file, git+ssh, persistent-https, x.y]\n")
      config = load(env)

      assert_equal 5, config.network_timeout
      assert_equal %w[ssh https file git+ssh persistent-https x.y], config.protocols
    end
  end

  def test_variables_are_parsed_from_strings_and_outrank_the_file
    with_sandbox do |env|
      write(env, "networkTimeout: 5\nprotocols: [ssh]\n")
      varied = load(env.merge('SLIPWAY_NETWORK_TIMEOUT' => '86400', 'SLIPWAY_PROTOCOLS' => 'https:file'))
      empty = load(env.merge('SLIPWAY_NETWORK_TIMEOUT' => '', 'SLIPWAY_PROTOCOLS' => ''))

      assert_equal [86_400, %w[https file]], [varied.network_timeout, varied.protocols]
      assert_equal [5, %w[ssh]], [empty.network_timeout, empty.protocols]
    end
  end

  def test_wrong_values_in_the_file_name_the_key
    with_sandbox do |env|
      ["networkTimeout: 0\n", "networkTimeout: -1\n", "networkTimeout: '60'\n", "networkTimeout: 1.5\n",
       "networkTimeout: true\n", "networkTimeout: 86401\n", "networkTimeout: 99999999999\n"].each do |text|
        assert_file_error '"networkTimeout" must be an integer from 1 to 86400', env, text
      end
    end
  end

  def test_protocols_must_be_a_list_of_transport_names
    with_sandbox do |env|
      ["protocols: ssh\n", "protocols: []\n", "protocols: [SSH]\n", "protocols: ['ssh:ext']\n",
       "protocols: ['https ext']\n", "protocols: [-x]\n", "protocols: [1ssh]\n", "protocols: [ssh, true]\n",
       "protocols: [ssh, null]\n", "protocols: [\"ssh\\n\"]\n", "protocols: ['']\n"].each do |text|
        assert_file_error "\"protocols\" #{PROTOCOLS}", env, text
      end
    end
  end

  def test_protocols_refuses_ext_and_fd_even_when_listed
    with_sandbox do |env|
      assert_config_error "SLIPWAY_PROTOCOLS: #{EXT}", env.merge('SLIPWAY_PROTOCOLS' => 'ext')
      assert_config_error "SLIPWAY_PROTOCOLS: #{FD}", env.merge('SLIPWAY_PROTOCOLS' => 'https:fd')
      assert_file_error "\"protocols\" #{EXT}", env, "protocols: [ssh, ext]\n"
      assert_file_error "\"protocols\" #{FD}", env, "protocols: [fd, https]\n"
      assert_file_error "\"protocols\" #{FD}", env, "protocols: [fd, ext]\n"
    end
  end

  def test_config_names_the_variables_that_supplied_a_value
    with_sandbox do |env|
      write(env, "protocols: [ssh]\ncolor: never\n")
      varied = env.merge('SLIPWAY_PROTOCOLS' => 'file', 'SLIPWAY_NETWORK_TIMEOUT' => '', 'SLIPWAY_COLOR' => 'always')

      assert_equal({ 'protocols' => 'SLIPWAY_PROTOCOLS', 'color' => 'SLIPWAY_COLOR' }, load(varied).variables)
      assert_equal({ 'protocols' => 'SLIPWAY_PROTOCOLS' }, load(varied, flags: { color: 'auto' }).variables)
      assert_empty load(env).variables
    end
  end

  def test_variables_are_validated_with_the_variable_as_prefix
    with_sandbox do |env|
      %w[x 0 -1 4.5 1m 86401 99999999999].each do |value|
        assert_config_error 'SLIPWAY_NETWORK_TIMEOUT: must be an integer from 1 to 86400',
                            env.merge('SLIPWAY_NETWORK_TIMEOUT' => value)
      end
      ['ssh::https', 'ssh:', ':ssh', 'ssh,https', 'SSH'].each do |value|
        assert_config_error "SLIPWAY_PROTOCOLS: #{PROTOCOLS_VARIABLE}", env.merge('SLIPWAY_PROTOCOLS' => value)
      end
    end
  end

  def test_a_setting_member_is_its_key_in_snake_case
    assert_equal %i[color editor group network_timeout protocols theme],
                 Slipway::Config::SETTINGS.map(&:attribute)
  end

  def test_the_man_page_shows_list_defaults_as_the_file_would_name_them
    assert_equal 'Transports git may use in network commands, as a list; any other transport is refused, and so ' \
                 'are ext and fd. Add file for local mirrors. Default: ssh, https.',
                 Slipway::Config::DOCUMENTATION.fetch('protocols')
  end
end
