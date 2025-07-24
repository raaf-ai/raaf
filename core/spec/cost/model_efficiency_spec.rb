# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Model Efficiency Analysis", :cost do
  let(:cost_tracker) { RAAF::Testing::CostTracker }
  let(:mock_provider) { create_mock_provider }

  describe "Model performance vs cost trade-offs" do
    let(:efficiency_models) do
      [
        { name: "gpt-3.5-turbo", cost_factor: 1, performance_score: 7 },
        { name: "gpt-4o-mini", cost_factor: 5, performance_score: 8 },
        { name: "gpt-4o", cost_factor: 10, performance_score: 9 },
        { name: "gpt-4", cost_factor: 30, performance_score: 9.5 }
      ]
    end

    it "identifies optimal model for task complexity" do
      simple_task_tokens = 100
      complex_task_tokens = 2000

      # For simple tasks, cheaper models should be more cost-effective
      simple_gpt35_cost = cost_tracker.estimate_cost(simple_task_tokens, "gpt-3.5-turbo")
      simple_gpt4_cost = cost_tracker.estimate_cost(simple_task_tokens, "gpt-4")

      cost_difference_simple = simple_gpt4_cost - simple_gpt35_cost
      expect(cost_difference_simple).to be > simple_gpt35_cost * 2 # GPT-4 costs 3x+ more

      # For complex tasks, cost per token difference is same but value may justify premium model
      complex_gpt35_cost = cost_tracker.estimate_cost(complex_task_tokens, "gpt-3.5-turbo")
      complex_gpt4_cost = cost_tracker.estimate_cost(complex_task_tokens, "gpt-4")

      expect(complex_gpt4_cost).to be > complex_gpt35_cost
    end
  end

  describe "Task-specific cost optimization" do
    it "validates costs for classification tasks" do
      mock_provider.add_response(
        "Category: Technical Support",
        usage: { prompt_tokens: 50, completion_tokens: 10, total_tokens: 60 }
      )

      classification_agent = create_test_agent(
        name: "ClassifierAgent",
        model: "gpt-4o-mini",
        instructions: "Classify the following request into categories"
      )

      runner = RAAF::Runner.new(agent: classification_agent, provider: mock_provider)

      with_cost_tracking do
        result = runner.run("I need help with my password reset")
        cost_tracker.track_usage(result.usage, model: "gpt-4o-mini")

        # Classification should be cheap and fast
        expect(result).to be_within_token_budget(100)
        expect(result).to be_within_cost_budget(0.001)
      end
    end

    it "validates costs for content generation tasks" do
      mock_provider.add_response(
        "Here's a comprehensive article about AI..." * 50,
        usage: { prompt_tokens: 200, completion_tokens: 800, total_tokens: 1000 }
      )

      content_agent = create_test_agent(
        name: "ContentAgent",
        model: "gpt-4o",
        instructions: "Write engaging, informative content"
      )

      runner = RAAF::Runner.new(agent: content_agent, provider: mock_provider)

      with_cost_tracking do
        result = runner.run("Write an article about artificial intelligence")
        cost_tracker.track_usage(result.usage, model: "gpt-4o")

        # Content generation requires more tokens but should be reasonable
        expect(result.usage[:total_tokens]).to be > 500
        expect(result).to be_within_token_budget(2000)
        expect(result).to be_within_cost_budget(0.05)
      end
    end

    it "validates costs for analysis tasks" do
      mock_provider.add_response(
        "Based on the data analysis...",
        usage: { prompt_tokens: 1000, completion_tokens: 500, total_tokens: 1500 }
      )

      analysis_agent = create_test_agent(
        name: "AnalystAgent",
        model: "gpt-4",
        instructions: "Perform detailed data analysis and provide insights"
      )

      runner = RAAF::Runner.new(agent: analysis_agent, provider: mock_provider)

      with_cost_tracking do
        result = runner.run("Analyze this quarterly sales data: [large dataset]")
        cost_tracker.track_usage(result.usage, model: "gpt-4")

        # Analysis tasks justify higher costs for better accuracy
        expect(result.usage[:total_tokens]).to be > 1000
        expect(cost_tracker.total_cost).to be > 0.02 # Higher cost acceptable for analysis
      end
    end
  end

  describe "Cost monitoring and alerts" do
    it "identifies cost anomalies" do
      baseline_usage = { total_tokens: 200 }
      anomaly_usage = { total_tokens: 5000 }

      baseline_cost = cost_tracker.estimate_cost(baseline_usage[:total_tokens], "gpt-4o")
      anomaly_cost = cost_tracker.estimate_cost(anomaly_usage[:total_tokens], "gpt-4o")

      cost_multiplier = anomaly_cost / baseline_cost
      expect(cost_multiplier).to be > 10 # 10x+ cost increase should trigger alert

      # Flag conversations that exceed baseline by significant margin
      expect(anomaly_cost).to be > 0.02 # Threshold for investigation
    end
  end

  describe "Cost optimization recommendations" do
    it "suggests model downgrade for simple tasks" do
      simple_task_results = []

      ["gpt-4", "gpt-4o", "gpt-4o-mini", "gpt-3.5-turbo"].each do |model|
        tokens = 100 # Simple classification task
        cost = cost_tracker.estimate_cost(tokens, model)

        simple_task_results << {
          model: model,
          cost: cost,
          cost_per_1k_tokens: cost * 10 # For 1K tokens
        }
      end

      # Sort by cost efficiency
      efficient_models = simple_task_results.sort_by { |result| result[:cost] }

      expect(efficient_models.first[:model]).to eq("gpt-3.5-turbo")
      expect(efficient_models.last[:model]).to eq("gpt-4")

      # Verify significant cost differences
      cheapest = efficient_models.first[:cost]
      most_expensive = efficient_models.last[:cost]
      expect(most_expensive / cheapest).to be > 10
    end

    it "identifies opportunities for context compression" do
      # Simulate conversation with growing context
      context_sizes = [100, 300, 600, 1000, 1500, 2000]
      context_costs = context_sizes.map do |size|
        cost_tracker.estimate_cost(size, "gpt-4o")
      end

      # Calculate marginal cost of additional context
      marginal_costs = context_costs.each_cons(2).map { |prev, curr| curr - prev }

      # Context compression becomes valuable when marginal cost increases significantly
      compression_threshold = marginal_costs.max * 0.5
      compression_opportunities = marginal_costs.count { |cost| cost > compression_threshold }

      expect(compression_opportunities).to be_positive
    end

    it "evaluates batch processing efficiency" do
      individual_requests = 10
      batch_size = 10

      # Individual processing
      individual_overhead = 20 # Base tokens per request
      individual_total_cost = individual_requests * cost_tracker.estimate_cost(100 + individual_overhead, "gpt-4o")

      # Batch processing
      batch_overhead = 30 # Slightly higher base for batch
      batch_total_cost = cost_tracker.estimate_cost((100 * batch_size) + batch_overhead, "gpt-4o")

      savings = individual_total_cost - batch_total_cost
      savings_percentage = (savings / individual_total_cost) * 100

      expect(savings).to be_positive
      expect(savings_percentage).to be > 10 # At least 10% savings from batching
    end
  end
end
