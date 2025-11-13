# frozen_string_literal: true

# Simple test runner for evaluators
require "bundler/setup"

# Load DSL components
require_relative "../lib/raaf/eval/dsl/field_context"
require_relative "../lib/raaf/eval/dsl/evaluator"

# Load all evaluator files
Dir[File.join(__dir__, "../lib/raaf/eval/evaluators/**/*.rb")].each { |file| require file }

# Simple test framework
def test(description, &block)
  print "Testing #{description}... "
  begin
    block.call
    puts "✅ PASSED"
    true
  rescue => e
    puts "❌ FAILED: #{e.message}"
    false
  end
end

def assert(condition, message = "Assertion failed")
  raise message unless condition
end

def assert_equal(expected, actual, message = nil)
  msg = message || "Expected #{expected.inspect}, got #{actual.inspect}"
  raise msg unless expected == actual
end

puts "\n=== Running Evaluator Tests ===\n\n"

# Test Performance evaluators
puts "Performance Evaluators:"

test "TokenEfficiency - passes under threshold" do
  evaluator = RAAF::Eval::Evaluators::Performance::TokenEfficiency.new
  result = { tokens: 110, baseline_tokens: 100 }
  context = RAAF::Eval::DSL::FieldContext.new(:tokens, result)
  
  eval_result = evaluator.evaluate(context, max_increase_pct: 15)
  assert eval_result[:passed], "Should pass with 10% increase under 15% threshold"
  assert eval_result[:score] > 0.5, "Score should be > 0.5"
end

test "Latency - validates response time" do
  evaluator = RAAF::Eval::Evaluators::Performance::Latency.new
  result = { latency_ms: 1500 }
  context = RAAF::Eval::DSL::FieldContext.new(:latency_ms, result)
  
  eval_result = evaluator.evaluate(context, max_ms: 2000)
  assert eval_result[:passed], "Should pass under threshold"
end

test "Throughput - validates tokens per second" do
  evaluator = RAAF::Eval::Evaluators::Performance::Throughput.new
  result = { tokens_per_second: 15 }
  context = RAAF::Eval::DSL::FieldContext.new(:tokens_per_second, result)
  
  eval_result = evaluator.evaluate(context, min_tps: 10)
  assert eval_result[:passed], "Should pass above minimum"
end

# Test Regression evaluators
puts "\nRegression Evaluators:"

test "NoRegression - detects no regression" do
  evaluator = RAAF::Eval::Evaluators::Regression::NoRegression.new
  result = { score: 0.85, baseline_score: 0.80 }
  context = RAAF::Eval::DSL::FieldContext.new(:score, result)
  
  eval_result = evaluator.evaluate(context)
  assert eval_result[:passed], "Should pass with improvement"
  assert_equal 1.0, eval_result[:score]
end

test "TokenRegression - checks token increase" do
  evaluator = RAAF::Eval::Evaluators::Regression::TokenRegression.new
  result = { tokens: 105, baseline_tokens: 100 }
  context = RAAF::Eval::DSL::FieldContext.new(:tokens, result)
  
  eval_result = evaluator.evaluate(context, max_pct: 10)
  assert eval_result[:passed], "Should pass with 5% increase"
end

test "LatencyRegression - checks latency increase" do
  evaluator = RAAF::Eval::Evaluators::Regression::LatencyRegression.new
  result = { latency_ms: 1100, baseline_latency_ms: 1000 }
  context = RAAF::Eval::DSL::FieldContext.new(:latency_ms, result)
  
  eval_result = evaluator.evaluate(context, max_ms: 200)
  assert eval_result[:passed], "Should pass with 100ms increase"
end

# Test Safety evaluators
puts "\nSafety Evaluators:"

test "BiasDetection - detects clean content" do
  evaluator = RAAF::Eval::Evaluators::Safety::BiasDetection.new
  result = { content: "The software engineer completed the project." }
  context = RAAF::Eval::DSL::FieldContext.new(:content, result)
  
  eval_result = evaluator.evaluate(context)
  assert eval_result[:passed], "Should pass with unbiased content"
end

test "ToxicityDetection - validates safe content" do
  evaluator = RAAF::Eval::Evaluators::Safety::ToxicityDetection.new
  result = { content: "Thank you for your help." }
  context = RAAF::Eval::DSL::FieldContext.new(:content, result)
  
  eval_result = evaluator.evaluate(context)
  assert eval_result[:passed], "Should pass with safe content"
end

test "Compliance - checks policy compliance" do
  evaluator = RAAF::Eval::Evaluators::Safety::Compliance.new
  result = { content: "Our product helps improve efficiency." }
  context = RAAF::Eval::DSL::FieldContext.new(:content, result)
  
  eval_result = evaluator.evaluate(context, policies: [:general])
  assert eval_result[:passed], "Should pass compliance check"
end

# Test Statistical evaluators
puts "\nStatistical Evaluators:"

test "Consistency - checks value consistency" do
  evaluator = RAAF::Eval::Evaluators::Statistical::Consistency.new
  result = { data: [10, 11, 10, 11, 10] }
  context = RAAF::Eval::DSL::FieldContext.new(:data, result)
  
  eval_result = evaluator.evaluate(context, std_dev: 0.15)
  assert eval_result[:passed], "Should pass with low variation"
end

test "StatisticalSignificance - validates p-value" do
  evaluator = RAAF::Eval::Evaluators::Statistical::StatisticalSignificance.new
  result = { data: { p_value: 0.03, sample_size: 100 } }
  context = RAAF::Eval::DSL::FieldContext.new(:data, result)
  
  eval_result = evaluator.evaluate(context, p_value: 0.05)
  assert eval_result[:passed], "Should pass with significant p-value"
end

test "EffectSize - validates Cohen's d" do
  evaluator = RAAF::Eval::Evaluators::Statistical::EffectSize.new
  result = { data: { cohen_d: 0.8 } }
  context = RAAF::Eval::DSL::FieldContext.new(:data, result)
  
  eval_result = evaluator.evaluate(context, cohen_d: 0.5)
  assert eval_result[:passed], "Should pass with large effect"
end

# Test Structural evaluators
puts "\nStructural Evaluators:"

test "JsonValidity - validates JSON" do
  evaluator = RAAF::Eval::Evaluators::Structural::JsonValidity.new
  result = { output: '{"name": "test", "value": 42}' }
  context = RAAF::Eval::DSL::FieldContext.new(:output, result)
  
  eval_result = evaluator.evaluate(context)
  assert eval_result[:passed], "Should pass with valid JSON"
end

test "SchemaMatch - validates schema" do
  evaluator = RAAF::Eval::Evaluators::Structural::SchemaMatch.new
  result = { output: { name: "test", age: 30 } }
  context = RAAF::Eval::DSL::FieldContext.new(:output, result)
  
  schema = {
    type: "object",
    required: ["name", "age"],
    properties: {
      name: { type: "string" },
      age: { type: "integer" }
    }
  }
  
  eval_result = evaluator.evaluate(context, schema: schema)
  assert eval_result[:passed], "Should match schema"
end

test "FormatCompliance - validates email" do
  evaluator = RAAF::Eval::Evaluators::Structural::FormatCompliance.new
  result = { output: "test@example.com" }
  context = RAAF::Eval::DSL::FieldContext.new(:output, result)
  
  eval_result = evaluator.evaluate(context, format: :email)
  assert eval_result[:passed], "Should pass email validation"
end

# Test LLM evaluators
puts "\nLLM Evaluators:"

test "LlmJudge - evaluates with criteria" do
  evaluator = RAAF::Eval::Evaluators::LLM::LlmJudge.new
  result = { output: "The capital of France is Paris." }
  context = RAAF::Eval::DSL::FieldContext.new(:output, result)
  
  eval_result = evaluator.evaluate(context, criteria: "accuracy, clarity")
  assert eval_result.key?(:passed), "Should have passed key"
  assert eval_result.key?(:score), "Should have score key"
end

test "QualityScore - assesses quality" do
  evaluator = RAAF::Eval::Evaluators::LLM::QualityScore.new
  result = { output: "A comprehensive solution with multiple steps and clear explanations." }
  context = RAAF::Eval::DSL::FieldContext.new(:output, result)
  
  eval_result = evaluator.evaluate(context, min_score: 0.5)
  assert eval_result.key?(:passed), "Should have passed key"
  assert eval_result[:details][:dimensions], "Should have dimensions"
end

test "RubricEvaluation - evaluates against rubric" do
  evaluator = RAAF::Eval::Evaluators::LLM::RubricEvaluation.new
  result = { output: "Clear analysis with supporting evidence." }
  context = RAAF::Eval::DSL::FieldContext.new(:output, result)
  
  rubric = {
    passing_score: 0.6,
    criteria: {
      clarity: { required_elements: ["clear", "analysis"] }
    }
  }
  
  eval_result = evaluator.evaluate(context, rubric: rubric)
  assert eval_result.key?(:passed), "Should have passed key"
  assert eval_result[:details][:rubric_scores], "Should have rubric scores"
end

puts "\n=== Test Summary ===\n"
puts "All tests completed!"
