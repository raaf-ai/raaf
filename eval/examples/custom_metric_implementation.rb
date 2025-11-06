# frozen_string_literal: true

# Custom Metric Implementation Example for RAAF Eval
#
# This example demonstrates how to implement custom domain-specific metrics
# for evaluating AI agent outputs.

require "raaf/eval"

puts "=== RAAF Eval Custom Metric Implementation ===\n\n"

# Example 1: Simple Synchronous Metric
# Measures output politeness by counting polite words
class PolitenessMetric < RAAF::Eval::Metrics::CustomMetric
  POLITE_WORDS = %w[
    please thank thanks appreciate kindly would could may might
    sorry apologize pardon excuse grateful wonderful excellent
  ].freeze

  def initialize
    super("politeness")
  end

  def calculate(baseline_span, result_span)
    baseline_output = extract_output(baseline_span)
    result_output = extract_output(result_span)

    {
      baseline_score: politeness_score(baseline_output),
      result_score: politeness_score(result_output),
      change: score_change(baseline_output, result_output),
      interpretation: interpret_change(baseline_output, result_output)
    }
  end

  private

  def extract_output(span)
    span.dig(:metadata, :output) || span.dig(:output) || ""
  end

  def politeness_score(text)
    return 0.0 if text.empty?

    words = text.downcase.split(/\s+/)
    polite_count = words.count { |word| POLITE_WORDS.include?(word) }

    # Normalize by text length
    (polite_count.to_f / words.length * 100).round(2)
  end

  def score_change(baseline_output, result_output)
    baseline = politeness_score(baseline_output)
    result = politeness_score(result_output)
    ((result - baseline) / baseline * 100).round(2)
  rescue ZeroDivisionError
    0.0
  end

  def interpret_change(baseline_output, result_output)
    change = score_change(baseline_output, result_output)

    if change > 10
      "significantly more polite"
    elsif change > 0
      "slightly more polite"
    elsif change < -10
      "significantly less polite"
    elsif change < 0
      "slightly less polite"
    else
      "similar politeness"
    end
  end
end

# Example 2: Code Quality Metric
# Evaluates code quality in agent responses
class CodeQualityMetric < RAAF::Eval::Metrics::CustomMetric
  def initialize
    super("code_quality")
  end

  def calculate(baseline_span, result_span)
    baseline_code = extract_code_blocks(extract_output(baseline_span))
    result_code = extract_code_blocks(extract_output(result_span))

    {
      baseline_code_blocks: baseline_code.length,
      result_code_blocks: result_code.length,
      baseline_quality: analyze_code_quality(baseline_code),
      result_quality: analyze_code_quality(result_code),
      improvement: quality_improvement(baseline_code, result_code)
    }
  end

  private

  def extract_output(span)
    span.dig(:metadata, :output) || span.dig(:output) || ""
  end

  def extract_code_blocks(text)
    # Extract code blocks from markdown
    text.scan(/```[\w]*\n(.*?)```/m).flatten
  end

  def analyze_code_quality(code_blocks)
    return { score: 0, checks: {} } if code_blocks.empty?

    total_score = 0
    checks = {}

    code_blocks.each do |code|
      # Check for comments
      has_comments = code.include?("#") || code.include?("//")
      total_score += 1 if has_comments

      # Check for proper indentation
      properly_indented = code.lines.none? { |line| line.start_with?(" ") && !line.start_with?("  ") }
      total_score += 1 if properly_indented

      # Check for variable names (not single letters)
      good_names = !code.match?(/\b[a-z]\s*=/)
      total_score += 1 if good_names

      checks[:has_comments] = has_comments
      checks[:properly_indented] = properly_indented
      checks[:good_variable_names] = good_names
    end

    { score: total_score, checks: checks }
  end

  def quality_improvement(baseline_code, result_code)
    baseline_quality = analyze_code_quality(baseline_code)[:score]
    result_quality = analyze_code_quality(result_code)[:score]

    result_quality - baseline_quality
  end
end

# Example 3: Response Time Sensitivity Metric
# Measures how well the agent responds to time-sensitive queries
class TimeSensitivityMetric < RAAF::Eval::Metrics::CustomMetric
  TIME_KEYWORDS = %w[
    now today tomorrow yesterday current recent latest
    urgent immediately asap deadline today's
  ].freeze

  def initialize
    super("time_sensitivity")
  end

  def calculate(baseline_span, result_span)
    baseline_output = extract_output(baseline_span)
    result_output = extract_output(result_span)
    baseline_input = extract_input(baseline_span)

    {
      input_time_sensitive: time_sensitive?(baseline_input),
      baseline_addressed_timing: addresses_timing?(baseline_output),
      result_addressed_timing: addresses_timing?(result_output),
      improvement: timing_improvement(baseline_output, result_output),
      recommendation: timing_recommendation(baseline_input, result_output)
    }
  end

  private

  def extract_output(span)
    span.dig(:metadata, :output) || span.dig(:output) || ""
  end

  def extract_input(span)
    messages = span.dig(:metadata, :messages) || []
    messages.last&.dig(:content) || ""
  end

  def time_sensitive?(text)
    TIME_KEYWORDS.any? { |keyword| text.downcase.include?(keyword) }
  end

  def addresses_timing?(text)
    # Check if response includes dates, times, or temporal references
    has_date = text.match?(/\d{4}-\d{2}-\d{2}|\d{1,2}\/\d{1,2}\/\d{2,4}/)
    has_time = text.match?(/\d{1,2}:\d{2}/)
    has_temporal = TIME_KEYWORDS.any? { |keyword| text.downcase.include?(keyword) }

    has_date || has_time || has_temporal
  end

  def timing_improvement(baseline_output, result_output)
    baseline_score = addresses_timing?(baseline_output) ? 1 : 0
    result_score = addresses_timing?(result_output) ? 1 : 0

    result_score - baseline_score
  end

  def timing_recommendation(input, output)
    if time_sensitive?(input) && !addresses_timing?(output)
      "Consider adding temporal context to the response"
    elsif !time_sensitive?(input) && addresses_timing?(output)
      "Good: Added helpful temporal context"
    elsif time_sensitive?(input) && addresses_timing?(output)
      "Excellent: Properly addressed time-sensitive query"
    else
      "No temporal concerns"
    end
  end
end

# Example 4: Async Metric (Simulated)
# Demonstrates async metric calculation
class SentimentAnalysisMetric < RAAF::Eval::Metrics::CustomMetric
  def initialize
    super("sentiment_analysis")
  end

  def async?
    true # This metric should be calculated asynchronously
  end

  def calculate(baseline_span, result_span)
    baseline_output = extract_output(baseline_span)
    result_output = extract_output(result_span)

    # Simulate async processing
    sleep(0.1) # In real implementation, this would be an API call

    {
      baseline_sentiment: analyze_sentiment(baseline_output),
      result_sentiment: analyze_sentiment(result_output),
      sentiment_shift: calculate_shift(baseline_output, result_output),
      async_processed: true,
      processing_time_ms: 100
    }
  end

  private

  def extract_output(span)
    span.dig(:metadata, :output) || span.dig(:output) || ""
  end

  def analyze_sentiment(text)
    # Simple sentiment analysis based on positive/negative words
    positive_words = %w[good great excellent wonderful amazing happy pleased delighted]
    negative_words = %w[bad terrible awful horrible sad disappointed frustrated angry]

    words = text.downcase.split(/\s+/)
    positive_count = words.count { |w| positive_words.include?(w) }
    negative_count = words.count { |w| negative_words.include?(w) }

    if positive_count > negative_count
      { sentiment: "positive", score: positive_count - negative_count }
    elsif negative_count > positive_count
      { sentiment: "negative", score: negative_count - positive_count }
    else
      { sentiment: "neutral", score: 0 }
    end
  end

  def calculate_shift(baseline_output, result_output)
    baseline = analyze_sentiment(baseline_output)
    result = analyze_sentiment(result_output)

    "#{baseline[:sentiment]} → #{result[:sentiment]}"
  end
end

# Example 5: Composite Metric
# Combines multiple metrics into a single score
class ComprehensiveQualityMetric < RAAF::Eval::Metrics::CustomMetric
  def initialize
    super("comprehensive_quality")
    @politeness = PolitenessMetric.new
    @time_sensitivity = TimeSensitivityMetric.new
  end

  def calculate(baseline_span, result_span)
    politeness_result = @politeness.calculate(baseline_span, result_span)
    time_result = @time_sensitivity.calculate(baseline_span, result_span)

    # Combine metrics into overall quality score
    quality_score = calculate_quality_score(politeness_result, time_result)

    {
      overall_quality: quality_score,
      components: {
        politeness: politeness_result[:result_score],
        time_sensitivity: time_result[:result_addressed_timing] ? 100 : 0
      },
      breakdown: {
        politeness: politeness_result,
        time_sensitivity: time_result
      }
    }
  end

  private

  def calculate_quality_score(politeness_result, time_result)
    # Weight: 60% politeness, 40% time sensitivity
    politeness_score = politeness_result[:result_score] || 0
    time_score = time_result[:result_addressed_timing] ? 100 : 0

    (politeness_score * 0.6 + time_score * 0.4).round(2)
  end
end

# Demonstration
puts "Registering custom metrics..."

# Register metrics
RAAF::Eval::Metrics::CustomMetric::Registry.register(PolitenessMetric.new)
RAAF::Eval::Metrics::CustomMetric::Registry.register(CodeQualityMetric.new)
RAAF::Eval::Metrics::CustomMetric::Registry.register(TimeSensitivityMetric.new)
RAAF::Eval::Metrics::CustomMetric::Registry.register(SentimentAnalysisMetric.new)
RAAF::Eval::Metrics::CustomMetric::Registry.register(ComprehensiveQualityMetric.new)

puts "Registered #{RAAF::Eval::Metrics::CustomMetric::Registry.all.length} custom metrics\n\n"

# Test spans
baseline_span = {
  span_id: "span_001",
  metadata: {
    output: "Thank you for your question. The capital of France is Paris. I hope this helps!",
    messages: [
      { role: "user", content: "What is the capital of France today?" }
    ]
  }
}

result_span = {
  span_id: "span_002",
  metadata: {
    output: "The capital of France is Paris. This has been the case since 1789.",
    messages: [
      { role: "user", content: "What is the capital of France today?" }
    ]
  }
}

# Test each metric
puts "Testing Politeness Metric:"
puts "-" * 50
politeness = RAAF::Eval::Metrics::CustomMetric::Registry.get("politeness")
result = politeness.calculate(baseline_span, result_span)
puts "Baseline score: #{result[:baseline_score]}%"
puts "Result score: #{result[:result_score]}%"
puts "Change: #{result[:change]}%"
puts "Interpretation: #{result[:interpretation]}\n\n"

puts "Testing Time Sensitivity Metric:"
puts "-" * 50
time_sensitivity = RAAF::Eval::Metrics::CustomMetric::Registry.get("time_sensitivity")
result = time_sensitivity.calculate(baseline_span, result_span)
puts "Input time sensitive: #{result[:input_time_sensitive]}"
puts "Baseline addressed timing: #{result[:baseline_addressed_timing]}"
puts "Result addressed timing: #{result[:result_addressed_timing]}"
puts "Recommendation: #{result[:recommendation]}\n\n"

puts "Testing Code Quality Metric:"
puts "-" * 50
code_span_baseline = {
  span_id: "span_003",
  metadata: {
    output: "Here's the code:\n```ruby\nx=5\nprint x\n```"
  }
}

code_span_result = {
  span_id: "span_004",
  metadata: {
    output: "Here's the code:\n```ruby\n# Define variable\nuser_age = 5\nputs user_age\n```"
  }
}

code_quality = RAAF::Eval::Metrics::CustomMetric::Registry.get("code_quality")
result = code_quality.calculate(code_span_baseline, code_span_result)
puts "Baseline code blocks: #{result[:baseline_code_blocks]}"
puts "Result code blocks: #{result[:result_code_blocks]}"
puts "Quality improvement: #{result[:improvement]}\n\n"

puts "Testing Async Sentiment Analysis Metric:"
puts "-" * 50
sentiment = RAAF::Eval::Metrics::CustomMetric::Registry.get("sentiment_analysis")
puts "Is async: #{sentiment.async?}"
result = sentiment.calculate(baseline_span, result_span)
puts "Baseline sentiment: #{result[:baseline_sentiment][:sentiment]} (score: #{result[:baseline_sentiment][:score]})"
puts "Result sentiment: #{result[:result_sentiment][:sentiment]} (score: #{result[:result_sentiment][:score]})"
puts "Sentiment shift: #{result[:sentiment_shift]}\n\n"

puts "Testing Comprehensive Quality Metric:"
puts "-" * 50
comprehensive = RAAF::Eval::Metrics::CustomMetric::Registry.get("comprehensive_quality")
result = comprehensive.calculate(baseline_span, result_span)
puts "Overall quality score: #{result[:overall_quality]}"
puts "Components:"
puts "  - Politeness: #{result[:components][:politeness]}"
puts "  - Time Sensitivity: #{result[:components][:time_sensitivity]}"
puts "\n"

puts "=== Custom metric implementation examples complete! ==="
puts "\nKey Takeaways:"
puts "1. Extend RAAF::Eval::Metrics::CustomMetric for custom metrics"
puts "2. Implement calculate(baseline_span, result_span) method"
puts "3. Set async? to true for async metrics"
puts "4. Register metrics with CustomMetric::Registry"
puts "5. Combine multiple metrics for comprehensive evaluation"
