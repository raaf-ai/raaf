# frozen_string_literal: true

# Benchmark examples report their measurements through this rather than `puts`,
# so a full run stays readable. Set RAAF_BENCHMARK_OUTPUT=1 to see the numbers.
module BenchmarkOutput
  def bench_puts(line = "")
    puts line if ENV["RAAF_BENCHMARK_OUTPUT"] # rubocop:disable RSpec/Output -- opt-in benchmark reporting
  end
end
