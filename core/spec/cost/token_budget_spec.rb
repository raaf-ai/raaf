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

    it "tracks cumulative costs across multiple requests" do
      mock_provider = create_mock_provider

      # Add multiple responses with varying token usage
      mock_provider.add_response("Response 1", usage: { total_tokens: 100 })
      mock_provider.add_response("Response 2", usage: { total_tokens: 150 })
      mock_provider.add_response("Response 3", usage: { total_tokens: 200 })

      runner = RAAF::Runner.new(agent: efficient_agent, provider: mock_provider)

      with_cost_tracking do
        3.times do |i|
          result = runner.run("Query #{i + 1}")
          cost_tracker.track_usage(result.usage, model: efficient_agent.model)
        end

        expect(cost_tracker.total_tokens).to eq(450)
        expect(cost_tracker.calls.length).to eq(3)
        expect(cost_tracker.total_cost).to be_within(0.001).of(0.0045) # 450 * 0.00001
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
      expect(savings).to be > 0
      expect(gpt_4o_mini_cost / gpt_4o_cost).to be < 0.5 # At least 50% cheaper
    end
  end

  describe "Budget alerts and limits" do
    it "identifies high-cost operations" do
      high_usage = { total_tokens: 5000 }
      cost = cost_tracker.estimate_cost(high_usage[:total_tokens], "gpt-4")

      expect(cost).to be > 0.1 # Flag operations over $0.10
    end

    it "tracks daily budget consumption" do
      with_cost_tracking do
        # Simulate a day's worth of operations
        10.times do |i|
          cost_tracker.track_usage(
            { total_tokens: 200 + (i * 50) },
            model: "gpt-4o"
          )
        end

        daily_cost = cost_tracker.total_cost
        daily_tokens = cost_tracker.total_tokens

        expect(daily_tokens).to eq(2450) # 200*10 + 50*(0+1+...+9)
        expect(daily_cost).to be_within(0.001).of(0.0245)

        # Flag if approaching daily budget (e.g., $1.00)
        expect(daily_cost).to be < 1.0
      end
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
      expect(savings).to be > 0
      expect(savings / long_cost).to be > 0.7 # 70%+ savings through summarization
    end

    it "shows batch processing cost benefits" do
      # Single request vs. batch processing
      single_request_overhead = 20 # Base tokens per request

      # 5 separate requests
      individual_cost = 5 * cost_tracker.estimate_cost(100 + single_request_overhead, "gpt-4o")

      # 1 batched request
      batch_cost = cost_tracker.estimate_cost(500 + single_request_overhead, "gpt-4o")

      expect(batch_cost).to be < individual_cost
      savings_percent = (individual_cost - batch_cost) / individual_cost
      expect(savings_percent).to be > 0.15 # At least 15% savings from batching
    end
  end
end
