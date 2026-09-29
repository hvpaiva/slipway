# frozen_string_literal: true

require 'test_helper'
require 'rbconfig'

# Every file under lib declares what it uses, so any one of them can be required on its own.
class RequireGraphTest < Minitest::Test
  LIB = File.expand_path('../../lib', __dir__)
  FILES = Dir.glob('**/*.rb', base: LIB).sort.freeze
  # One interpreter forks once per file; a fresh process per file would cost a second each.
  SCRIPT = <<~RUBY
    failures = ARGV.select do |file|
      pid = fork do
        $stderr.reopen(File::NULL)
        require File.join(Dir.pwd, file)
        exit!(0)
      rescue Exception # rubocop:disable Lint/RescueException
        exit!(1)
      end
      !Process.wait2(pid).last.success?
    end
    puts failures
  RUBY

  def test_every_lib_file_loads_on_its_own
    out, err, status = Open3.capture3(RbConfig.ruby, '-w', '-I', LIB, '-e', SCRIPT, *FILES, chdir: LIB)

    assert_predicate status, :success?, err
    assert_empty out.split, 'these files do not load on their own'
    assert_operator FILES.size, :>, 40
  end
end
