# frozen_string_literal: true

module Slipway
  module Git
    # `from` and `to` are the full object names the branch pointed at before and after the move,
    # and `count` the commits it dropped: 0, with `to` equal to `from`, when the branch already
    # stood at the target.
    MoveBack = Data.define(:from, :to, :count) do
      def moved? = to != from
    end
  end
end
