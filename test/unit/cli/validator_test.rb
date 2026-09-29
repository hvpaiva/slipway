# frozen_string_literal: true

require 'test_helper'

class ValidatorTest < Minitest::Test
  def setup
    @fixture = FixtureRegistry.new
  end

  def test_missing_required_positional
    error = usage_error('get', [], {})

    assert_equal 'missing required argument "TYPE"', error.message
    assert_equal "See 'slipway get --help' for usage.", error.hint
  end

  def test_unexpected_positional_beyond_a_fixed_arity
    error = usage_error('create', %w[projects alpha extra], { path: '/x' })

    assert_equal 'unexpected argument "extra"', error.message
    assert_equal "See 'slipway create --help' for usage.", error.hint
  end

  def test_variadic_tail_accepts_any_count
    validate('get', %w[projects alpha beta gamma], { output: 'table' })
    pass
  end

  def test_positional_enum
    error = usage_error('get', %w[pods], {})

    assert_equal 'invalid argument "pods" for TYPE: must be one of projects, groups', error.message
  end

  def test_required_option
    error = usage_error('create', %w[projects alpha], { path: nil })

    assert_equal 'required flag(s) "--path" not set', error.message
  end

  def test_option_enum_uses_the_label
    error = usage_error('get', %w[projects], { output: 'xml' })

    assert_equal 'invalid argument "xml" for "-o, --output FORMAT": must be one of table, wide, json, yaml, name',
                 error.message
  end

  def test_global_option_enum_is_checked_too
    error = usage_error('get', %w[projects], { color: 'sometimes' })

    assert_equal 'invalid argument "sometimes" for "--color[=WHEN]": must be one of auto, always, never', error.message
  end

  def test_valid_input_passes
    validate('create', %w[projects alpha], { path: '/x', dry_run: 'client', color: 'auto' })
    validate('get', %w[groups], { output: 'json' })
    pass
  end

  private

  def validate(name, args, opts)
    command, path = @fixture.registry.resolve([name])
    Slipway::CLI::Validator.new(command, path, @fixture.registry).call(args, opts)
  end

  def usage_error(name, args, opts)
    assert_raises(Slipway::CLI::UsageError) { validate(name, args, opts) }
  end
end
