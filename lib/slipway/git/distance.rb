# frozen_string_literal: true

module Slipway
  module Git
    # Where HEAD stands against another commit: +ahead+ counts the commits only HEAD reaches,
    # +behind+ the ones only the other commit reaches, and +off_upstream+ the ones the other commit
    # reaches and @{upstream} does not. That last count is taken only when HEAD is behind the other
    # commit on a branch whose upstream exists, and is nil otherwise.
    Distance = Data.define(:ahead, :behind, :off_upstream) do
      def initialize(ahead:, behind:, off_upstream: nil) = super
    end
  end
end
