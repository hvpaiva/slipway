# frozen_string_literal: true

# A real Runner that also keeps the arguments of every git command it started.
class RecordingRunner < Slipway::Git::Runner
  attr_reader :commands

  def initialize(...)
    super
    @commands = []
  end

  def run(path, *args, **)
    @commands << args
    super
  end
end
