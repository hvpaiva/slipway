# frozen_string_literal: true

require 'rbconfig'

module EditorScripts
  # +code+ runs once per line on $_. GNU sed's -i and \n have no BSD counterpart, so the
  # scripts edit through the interpreter that runs the suite.
  def rewrite(code) = "#{RbConfig.ruby} -pi -e '#{code}' \"$1\""
  module_function :rewrite

  ADD_TEAM = '$_ << "    team: core\n" if $_ == "    lang: rust\n"'
  DESCRIBE_GROUP = '$_ = "spec:\n  description: Day job\n" if $_ == "spec: {}\n"'
  MOVE = '$_.sub!("~/dev/hldr", "~/dev/moved")'
end
