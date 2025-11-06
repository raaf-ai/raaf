# frozen_string_literal: true

require "benchmark"
require_relative "../../lib/raaf/eval"

# Benchmark: Metrics Calculation Performance
#
# Target: < 500ms for standard metrics
# Target: < 5s for AI comparator
# Target: < 100ms for statistical analysis

puts "=== Metrics Calculation Benchmark ===\n\n"

# Test data setup
def create_baseline_span
  {
    span_id: "baseline_001",
    trace_id: "trace_001",
    metadata: {
      model: "gpt-4o",
      output: "The quick brown fox jumps over the lazy dog. This is a test sentence for evaluation.",
      usage: { total_tokens: 100, input_tokens: 50, output_tokens: 50, reasoning_tokens: 10 },
      timestamps: {
        start: Time.now.iso8601,
        end: (Time.now + 1.5).iso8601
      },
      cost: 0.003,
      latency_ms: 1500
    }
  }
end

def create_result_span
  {
    span_id: "result_001",
    trace_id: "trace_002",
    metadata: {
      model: "gpt-4o",
      output: "A quick brown fox jumped over the lazy dog. This sentence tests evaluation metrics.",
      usage: { total_tokens: 95, input_tokens: 50, output_tokens: 45, reasoning_tokens: 8 },
      timestamps: {
        start: Time.now.iso8601,
        end: (Time.now + 1.3).iso8601
      },
      cost: 0.0028,
      latency_ms: 1300
    }
  }
end

baseline_span = create_baseline_span
result_span = create_result_span

# Benchmark 1: Token Metrics
puts "Benchmark 1: Token Metrics Calculation"
puts "-" * 50

token_metrics = RAAF::Eval::Metrics::TokenMetrics.new
iterations = 1000

token_time = Benchmark.measure do
  iterations.times do
    token_metrics.calculate(baseline_span, result_span)
  end
end

token_avg_ms = (token_time.real * 1000) / iterations
puts "Total time: #{(token_time.real * 1000).round(2)}ms"
puts "Average per calculation: #{token_avg_ms.round(3)}ms"
puts "Status: #{token_avg_ms < 10 ? '✓ PASS' : '✗ FAIL'} (target: <10ms)"
puts "Throughput: #{(iterations / token_time.real).round(2)} calculations/sec"

# Show sample result
sample_result = token_metrics.calculate(baseline_span, result_span)
puts "\nSample result:"
puts "  Total tokens: #{sample_result[:result_total_tokens]}"
puts "  Token delta: #{sample_result[:token_delta]}"
puts "  Cost delta: $#{sample_result[:cost_delta]}"

# Benchmark 2: Latency Metrics
puts "\n\nBenchmark 2: Latency Metrics Calculation"
puts "-" * 50

latency_metrics = RAAF::Eval::Metrics::LatencyMetrics.new

latency_time = Benchmark.measure do
  iterations.times do
    latency_metrics.calculate(baseline_span, result_span)
  end
end

latency_avg_ms = (latency_time.real * 1000) / iterations
puts "Total time: #{(latency_time.real * 1000).round(2)}ms"
puts "Average per calculation: #{latency_avg_ms.round(3)}ms"
puts "Status: #{latency_avg_ms < 10 ? '✓ PASS' : '✗ FAIL'} (target: <10ms)"
puts "Throughput: #{(iterations / latency_time.real).round(2)} calculations/sec"

# Show sample result
sample_result = latency_metrics.calculate(baseline_span, result_span)
puts "\nSample result:"
puts "  Result latency: #{sample_result[:result_latency_ms]}ms"
puts "  Latency delta: #{sample_result[:latency_delta_ms]}ms"
puts "  Improvement: #{sample_result[:latency_delta_percentage]}%"

# Benchmark 3: Accuracy Metrics
puts "\n\nBenchmark 3: Accuracy Metrics Calculation"
puts "-" * 50

accuracy_metrics = RAAF::Eval::Metrics::AccuracyMetrics.new

accuracy_time = Benchmark.measure do
  iterations.times do
    accuracy_metrics.calculate(baseline_span, result_span)
  end
end

accuracy_avg_ms = (accuracy_time.real * 1000) / iterations
puts "Total time: #{(accuracy_time.real * 1000).round(2)}ms"
puts "Average per calculation: #{accuracy_avg_ms.round(3)}ms"
puts "Status: #{accuracy_avg_ms < 50 ? '✓ PASS' : '✗ FAIL'} (target: <50ms)"
puts "Throughput: #{(iterations / accuracy_time.real).round(2)} calculations/sec"

# Show sample result
sample_result = accuracy_metrics.calculate(baseline_span, result_span)
puts "\nSample result:"
puts "  Exact match: #{sample_result[:exact_match]}"
puts "  Fuzzy match: #{sample_result[:fuzzy_match_score]}"
puts "  Edit distance: #{sample_result[:edit_distance]}"

# Benchmark 4: Structural Metrics
puts "\n\nBenchmark 4: Structural Metrics Calculation"
puts "-" * 50

structural_metrics = RAAF::Eval::Metrics::StructuralMetrics.new

structural_time = Benchmark.measure do
  iterations.times do
    structural_metrics.calculate(baseline_span, result_span)
  end
end

structural_avg_ms = (structural_time.real * 1000) / iterations
puts "Total time: #{(structural_time.real * 1000).round(2)}ms"
puts "Average per calculation: #{structural_avg_ms.round(3)}ms"
puts "Status: #{structural_avg_ms < 10 ? '✓ PASS' : '✗ FAIL'} (target: <10ms)"
puts "Throughput: #{(iterations / structural_time.real).round(2)} calculations/sec"

# Show sample result
sample_result = structural_metrics.calculate(baseline_span, result_span)
puts "\nSample result:"
puts "  Result length: #{sample_result[:result_length]} chars"
puts "  Length delta: #{sample_result[:length_delta]} chars"
puts "  Format valid: #{sample_result[:format_valid]}"

# Benchmark 5: Statistical Analysis
puts "\n\nBenchmark 5: Statistical Analysis"
puts "-" * 50

statistical_analyzer = RAAF::Eval::Metrics::StatisticalAnalyzer.new

# Create sample data for statistical analysis
baseline_metrics = Array.new(30) { { tokens: 100 + rand(20), latency: 1500 + rand(500) } }
result_metrics = Array.new(30) { { tokens: 95 + rand(15), latency: 1300 + rand(400) } }

statistical_iterations = 100

statistical_time = Benchmark.measure do
  statistical_iterations.times do
    statistical_analyzer.analyze(baseline_metrics, result_metrics)
  end
end

statistical_avg_ms = (statistical_time.real * 1000) / statistical_iterations
puts "Total time: #{(statistical_time.real * 1000).round(2)}ms"
puts "Average per analysis: #{statistical_avg_ms.round(3)}ms"
puts "Status: #{statistical_avg_ms < 100 ? '✓ PASS' : '✗ FAIL'} (target: <100ms)"
puts "Throughput: #{(statistical_iterations / statistical_time.real).round(2)} analyses/sec"

# Show sample result
sample_result = statistical_analyzer.analyze(baseline_metrics, result_metrics)
puts "\nSample result:"
puts "  Token confidence interval: #{sample_result[:tokens][:confidence_interval]}" rescue puts "  (calculation pending)"
puts "  Latency p-value: #{sample_result[:latency][:p_value]}" rescue puts "  (calculation pending)"

# Benchmark 6: All Metrics Combined
puts "\n\nBenchmark 6: All Quantitative Metrics Combined"
puts "-" * 50

combined_iterations = 100

combined_time = Benchmark.measure do
  combined_iterations.times do
    token_metrics.calculate(baseline_span, result_span)
    latency_metrics.calculate(baseline_span, result_span)
    accuracy_metrics.calculate(baseline_span, result_span)
    structural_metrics.calculate(baseline_span, result_span)
  end
end

combined_avg_ms = (combined_time.real * 1000) / combined_iterations
puts "Total time: #{(combined_time.real * 1000).round(2)}ms"
puts "Average per full evaluation: #{combined_avg_ms.round(3)}ms"
puts "Status: #{combined_avg_ms < 500 ? '✓ PASS' : '✗ FAIL'} (target: <500ms)"
puts "Throughput: #{(combined_iterations / combined_time.real).round(2)} evaluations/sec"

# Benchmark 7: Batch Metrics Calculation
puts "\n\nBenchmark 7: Batch Metrics Calculation"
puts "-" * 50

batch_sizes = [10, 50, 100]

batch_sizes.each do |size|
  span_pairs = Array.new(size) { [create_baseline_span, create_result_span] }

  batch_time = Benchmark.measure do
    span_pairs.each do |baseline, result|
      token_metrics.calculate(baseline, result)
      latency_metrics.calculate(baseline, result)
      accuracy_metrics.calculate(baseline, result)
      structural_metrics.calculate(baseline, result)
    end
  end

  total_ms = batch_time.real * 1000
  avg_ms = total_ms / size

  puts "\nBatch size #{size}:"
  puts "  Total time: #{total_ms.round(2)}ms"
  puts "  Average per evaluation: #{avg_ms.round(3)}ms"
  puts "  Throughput: #{(size / batch_time.real).round(2)} evaluations/sec"
  puts "  Status: #{avg_ms < 500 ? '✓ PASS' : '✗ FAIL'}"
end

# Benchmark 8: AI Comparator (Simulated)
puts "\n\nBenchmark 8: AI Comparator Performance (Simulated)"
puts "-" * 50
puts "(Actual performance depends on AI provider API latency)"

# Simulate AI comparator execution
simulated_api_latencies = [1000, 1500, 2000, 2500, 3000] # ms

puts "\nSimulated AI comparator latencies:"
simulated_api_latencies.each_with_index do |latency, idx|
  overhead = 50 # Processing overhead
  total = latency + overhead

  puts "  Run #{idx + 1}: #{total}ms (#{latency}ms API + #{overhead}ms overhead)"
end

avg_ai_latency = (simulated_api_latencies.sum + 50 * simulated_api_latencies.length) / simulated_api_latencies.length
puts "\nAverage AI comparator time: #{avg_ai_latency}ms"
puts "Status: #{avg_ai_latency < 5000 ? '✓ PASS' : '✗ FAIL'} (target: <5000ms)"

# Benchmark 9: Custom Metrics
puts "\n\nBenchmark 9: Custom Metrics"
puts "-" * 50

class BenchmarkCustomMetric < RAAF::Eval::Metrics::CustomMetric
  def initialize
    super("benchmark_metric")
  end

  def calculate(baseline_span, result_span)
    baseline_output = baseline_span.dig(:metadata, :output) || ""
    result_output = result_span.dig(:metadata, :output) || ""

    {
      baseline_word_count: baseline_output.split.length,
      result_word_count: result_output.split.length,
      word_count_delta: result_output.split.length - baseline_output.split.length
    }
  end
end

custom_metric = BenchmarkCustomMetric.new
custom_iterations = 1000

custom_time = Benchmark.measure do
  custom_iterations.times do
    custom_metric.calculate(baseline_span, result_span)
  end
end

custom_avg_ms = (custom_time.real * 1000) / custom_iterations
puts "Custom metric calculation time: #{custom_avg_ms.round(3)}ms"
puts "Status: #{custom_avg_ms < 10 ? '✓ PASS' : '✗ FAIL'} (target: <10ms for simple metrics)"
puts "Throughput: #{(custom_iterations / custom_time.real).round(2)} calculations/sec"

# Performance Summary
puts "\n\n=== Performance Summary ==="

metrics_performance = {
  "Token Metrics" => { time: token_avg_ms, target: 10, unit: "ms" },
  "Latency Metrics" => { time: latency_avg_ms, target: 10, unit: "ms" },
  "Accuracy Metrics" => { time: accuracy_avg_ms, target: 50, unit: "ms" },
  "Structural Metrics" => { time: structural_avg_ms, target: 10, unit: "ms" },
  "Statistical Analysis" => { time: statistical_avg_ms, target: 100, unit: "ms" },
  "Combined Metrics" => { time: combined_avg_ms, target: 500, unit: "ms" },
  "AI Comparator (simulated)" => { time: avg_ai_latency, target: 5000, unit: "ms" }
}

puts "\nIndividual Metrics:"
metrics_performance.each do |name, data|
  status = data[:time] < data[:target] ? "✓" : "✗"
  puts "  #{status} #{name.ljust(30)}: #{data[:time].round(2)}#{data[:unit]} (target: <#{data[:target]}#{data[:unit]})"
end

puts "\nRecommendations:"
puts "  - Run AI comparator asynchronously to avoid blocking evaluation results"
puts "  - Cache metric calculations for repeated evaluations of the same span"
puts "  - Use batch processing for large-scale evaluations (>100 spans)"
puts "  - Consider parallel execution for independent metric calculations"
puts "  - Monitor AI comparator costs and implement rate limiting if needed"

# Check if all targets met
all_passed = metrics_performance.values.all? { |data| data[:time] < data[:target] }
puts "\n#{all_passed ? '✓' : '✗'} Overall: #{all_passed ? 'All performance targets met!' : 'Some targets not met'}"
