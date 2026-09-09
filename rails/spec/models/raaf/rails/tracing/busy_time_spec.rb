# frozen_string_literal: true

require "rails_helper"

# Summed durations are not elapsed time, and the two cases that pull them apart
# are spans that ran side by side and a span nested inside another.
RSpec.describe RAAF::Rails::Tracing::BusyTime do
  def at(seconds) = Time.zone.at(seconds)

  describe ".total_ms" do
    it "totals intervals that do not touch" do
      total = described_class.total_ms([[at(0), at(1)], [at(5), at(7)]])

      expect(total).to eq(3000.0)
    end

    # Two seconds of work spread over two workers is still two seconds of
    # elapsed time, not three.
    it "counts a stretch two overlapping intervals share only once" do
      total = described_class.total_ms([[at(0), at(2)], [at(1), at(3)]])

      expect(total).to eq(3000.0)
    end

    # A nested span adds nothing to the time its parent was already running.
    it "adds nothing for an interval contained in another" do
      total = described_class.total_ms([[at(0), at(10)], [at(2), at(4)]])

      expect(total).to eq(10_000.0)
    end

    it "joins intervals that meet exactly" do
      total = described_class.total_ms([[at(0), at(1)], [at(1), at(2)]])

      expect(total).to eq(2000.0)
    end

    it "does not depend on the order it is given them in" do
      total = described_class.total_ms([[at(5), at(7)], [at(1), at(3)], [at(2), at(6)]])

      expect(total).to eq(6000.0)
    end

    # A span still running has no end recorded, and one whose clock went
    # backwards describes no stretch of time. Neither can be measured, so
    # neither is counted.
    it "drops intervals missing an end or finishing before they start" do
      total = described_class.total_ms([[at(0), nil], [at(9), at(4)], [nil, at(3)], [at(0), at(1)]])

      expect(total).to eq(1000.0)
    end

    it "is zero for nothing at all" do
      expect(described_class.total_ms([])).to eq(0.0)
    end
  end
end
