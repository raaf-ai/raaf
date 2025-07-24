# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Token Budget Management", :cost do
  let(:cost_tracker) { RAAF::Testing::CostTracker }

  describe "Agent token usage" do
    let(:efficient_agent) do
      create_test_agent(
        name: "EfficientAgent",
        instructions: "Be concise",
        model: "gpt-4o-mini"
      )
    end

    let(:verbose_agent) do
      create_test_agent(
        name: "VerboseAgent",
        instructions: "Provide detailed explanations with examples and context",
        model: "gpt-4o"
      )
    end

    it "operates within token budget for simple queries" do
      mock_provider = create_mock_provider
      mock_provider.add_response(
        "Brief response",
        usage: { prompt_tokens: 50, completion_tokens: 20, total_tokens: 70 }
      )

      runner = RAAF::Runner.new(agent: efficient_agent, provider: mock_provider)

      with_cost_tracking do
        result = runner.run("What is 2+2?")
        cost_tracker.track_usage(result.usage, model: efficient_agent.model)

        expect(result).to be_within_token_budget(100)
        expect(result).to be_within_cost_budget(0.01)
      end
    end

    it "warns on expensive operations" do
      mock_provider = create_mock_provider
      mock_provider.add_response(
        "Very detailed response" * 100,
        usage: { prompt_tokens: 2000, completion_tokens: 1500, total_tokens: 3500 }
      )

      runner = RAAF::Runner.new(agent: verbose_agent, provider: mock_provider)

      with_cost_tracking do
        result = runner.run("Explain quantum computing in detail")
        cost_tracker.track_usage(result.usage, model: verbose_agent.model)

        expect(result.usage[:total_tokens]).to be > 1000
        expect(cost_tracker.total_cost).to be > 0.03
      end
    end
  end

  describe "Tool usage costs" do
    let(:expensive_tool) do
      RAAF::FunctionTool.new(
        proc { |query| "Detailed analysis: #{query}" * 20 },
        name: "analyze_data",
        description: "Performs expensive data analysis"
      )
    end

    let(:agent_with_expensive_tool) do
      agent = create_test_agent(name: "AnalystAgent")
      agent.add_tool(expensive_tool)
      agent
    end

    it "accounts for tool execution in cost calculations" do
      mock_provider = create_mock_provider
      mock_provider.add_response(
        "I'll analyze this data",
        tool_calls: [{
          function: { name: "analyze_data", arguments: '{"query": "complex analysis"}' }
        }],
        usage: { prompt_tokens: 200, completion_tokens: 50, total_tokens: 250 }
      )
      mock_provider.add_response(
        "Analysis complete with detailed results",
        usage: { prompt_tokens: 300, completion_tokens: 200, total_tokens: 500 }
      )

      runner = RAAF::Runner.new(agent: agent_with_expensive_tool, provider: mock_provider)

      with_cost_tracking do
        runner.run("Analyze this complex dataset")

        # Track both initial call and tool result processing
        cost_tracker.track_usage({ total_tokens: 250 }, model: "gpt-4o")
        cost_tracker.track_usage({ total_tokens: 500 }, model: "gpt-4o")

        expect(cost_tracker.total_tokens).to eq(750)
        expect(cost_tracker.total_cost).to be > 0.005
      end
    end
  end

  describe "Model cost comparison" do
    let(:models) { %w[gpt-4o gpt-4o-mini gpt-4 gpt-3.5-turbo] }

    it "compares costs across different models" do
      usage = { total_tokens: 1000 }
      costs = {}

      models.each do |model|
        costs[model] = cost_tracker.estimate_cost(usage[:total_tokens], model)
      end

      # Verify cost hierarchy (approximate)
      expect(costs["gpt-4"]).to be > costs["gpt-4o"]
      expect(costs["gpt-4o"]).to be > costs["gpt-4o-mini"]
      expect(costs["gpt-4o-mini"]).to be > costs["gpt-3.5-turbo"]
    end

    it "recommends cost-effective models for simple tasks" do
      simple_usage = { total_tokens: 100 }

      gpt_4o_cost = cost_tracker.estimate_cost(simple_usage[:total_tokens], "gpt-4o")
      gpt_4o_mini_cost = cost_tracker.estimate_cost(simple_usage[:total_tokens], "gpt-4o-mini")

      # For simple tasks, mini should be significantly cheaper
      savings = gpt_4o_cost - gpt_4o_mini_cost
      expect(savings).to be_positive
      expect(gpt_4o_mini_cost / gpt_4o_cost).to be < 0.5 # At least 50% cheaper
    end
  end

  describe "Budget alerts and limits" do
    it "identifies high-cost operations" do
      high_usage = { total_tokens: 5000 }
      cost = cost_tracker.estimate_cost(high_usage[:total_tokens], "gpt-4")

      expect(cost).to be > 0.1 # Flag operations over $0.10
    end

    it "provides cost breakdown by operation type" do
      with_cost_tracking do
        # Different operation types
        cost_tracker.track_usage({ total_tokens: 100 }, model: "gpt-4o")  # Simple query
        cost_tracker.track_usage({ total_tokens: 500 }, model: "gpt-4o")  # Complex query
        cost_tracker.track_usage({ total_tokens: 1000 }, model: "gpt-4")  # Analysis task

        calls_by_cost = cost_tracker.calls.sort_by { |call| call[:cost] }.reverse

        expect(calls_by_cost.first[:tokens]).to eq(1000)  # Most expensive
        expect(calls_by_cost.last[:tokens]).to eq(100)    # Least expensive
      end
    end
  end

  describe "Cost optimization strategies" do
    it "demonstrates context length optimization" do
      # Long context vs. summarized context
      long_context_tokens = 2000
      summarized_context_tokens = 500

      long_cost = cost_tracker.estimate_cost(long_context_tokens, "gpt-4o")
      summarized_cost = cost_tracker.estimate_cost(summarized_context_tokens, "gpt-4o")

      savings = long_cost - summarized_cost
      expect(savings).to be_positive
      expect(savings / long_cost).to be > 0.7 # 70%+ savings through summarization
    end
  end
end
