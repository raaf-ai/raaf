# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RAAF::Eval::RunResultAdapter do
  let(:agent) do
    RAAF::Agent.new(
      name: "TestAgent",
      instructions: "You are a test assistant",
      model: "gpt-4o",
      temperature: 0.7,
      max_tokens: 100
    )
  end

  let(:run_result) do
    RAAF::RunResult.new(
      agent_name: "TestAgent",
      messages: [
        { role: "user", content: "What is 2+2?" },
        { role: "assistant", content: "2+2 equals 4" }
      ],
      usage: {
        total_tokens: 50,
        input_tokens: 10,
        output_tokens: 40,
        output_tokens_details: { reasoning_tokens: 5 }
      },
      final_output: "2+2 equals 4",
      turns: 1
    )
  end

  describe '.to_span' do
    context 'with valid RunResult' do
      it 'converts RunResult to span format' do
        span = described_class.to_span(run_result, agent: agent)

        expect(span).to be_a(Hash)
        expect(span[:span_id]).to be_a(String)
        expect(span[:trace_id]).to be_a(String)
        expect(span[:span_type]).to eq("agent")
        expect(span[:source]).to eq("run_result")
      end

      it 'extracts agent name' do
        span = described_class.to_span(run_result, agent: agent)

        expect(span[:agent_name]).to eq("TestAgent")
      end

      it 'extracts model from agent' do
        span = described_class.to_span(run_result, agent: agent)

        expect(span[:model]).to eq("gpt-4o")
      end

      it 'extracts instructions from agent' do
        span = described_class.to_span(run_result, agent: agent)

        expect(span[:instructions]).to eq("You are a test assistant")
      end

      it 'extracts parameters from agent' do
        span = described_class.to_span(run_result, agent: agent)

        expect(span[:parameters]).to include(
          temperature: 0.7,
          max_tokens: 100
        )
      end

      it 'extracts input messages' do
        span = described_class.to_span(run_result, agent: agent)

        expect(span[:input_messages]).to eq([
          { role: "user", content: "What is 2+2?" }
        ])
      end

      it 'extracts output messages' do
        span = described_class.to_span(run_result, agent: agent)

        expect(span[:output_messages]).to eq([
          { role: "assistant", content: "2+2 equals 4" }
        ])
      end

      it 'builds metadata with token usage' do
        span = described_class.to_span(run_result, agent: agent)

        expect(span[:metadata]).to include(
          tokens: 50,
          input_tokens: 10,
          output_tokens: 40,
          reasoning_tokens: 5,
          output: "2+2 equals 4",
          turns: 1
        )
      end

      it 'includes created_at timestamp' do
        span = described_class.to_span(run_result, agent: agent)

        expect(span[:created_at]).to be_a(Time)
        expect(span[:created_at]).to be_within(1.second).of(Time.now.utc)
      end
    end

    context 'without agent reference' do
      let(:run_result_with_data) do
        result = run_result
        result.instance_variable_set(:@data, { model: "gpt-3.5-turbo", instructions: "Fallback instructions" })
        result
      end

      it 'falls back to RunResult data for model' do
        span = described_class.to_span(run_result_with_data)

        expect(span[:model]).to eq("gpt-3.5-turbo")
      end

      it 'falls back to RunResult data for instructions' do
        span = described_class.to_span(run_result_with_data)

        expect(span[:instructions]).to eq("Fallback instructions")
      end

      it 'uses empty hash for parameters' do
        span = described_class.to_span(run_result)

        expect(span[:parameters]).to eq({})
      end

      it 'defaults to "unknown" model if not in data' do
        span = described_class.to_span(run_result)

        expect(span[:model]).to eq("unknown")
      end

      it 'defaults to empty string for instructions if not in data' do
        span = described_class.to_span(run_result)

        expect(span[:instructions]).to eq("")
      end
    end

    context 'with empty messages' do
      let(:empty_run_result) do
        RAAF::RunResult.new(
          agent_name: "TestAgent",
          messages: [],
          usage: {}
        )
      end

      it 'handles empty messages gracefully' do
        span = described_class.to_span(empty_run_result, agent: agent)

        expect(span[:input_messages]).to eq([])
        expect(span[:output_messages]).to eq([])
      end
    end

    context 'with tool results' do
      let(:run_result_with_tools) do
        RAAF::RunResult.new(
          agent_name: "ToolAgent",
          messages: [
            { role: "user", content: "Search for Ruby" },
            { role: "assistant", content: "Here are the results" }
          ],
          usage: { total_tokens: 100 },
          tool_results: [
            { tool: "search", result: "Ruby documentation..." }
          ]
        )
      end

      it 'includes tool results in metadata' do
        span = described_class.to_span(run_result_with_tools, agent: agent)

        expect(span[:metadata][:tool_results]).to eq([
          { tool: "search", result: "Ruby documentation..." }
        ])
      end
    end

    context 'validation' do
      it 'raises error for nil RunResult' do
        expect {
          described_class.to_span(nil)
        }.to raise_error(ArgumentError, "run_result cannot be nil")
      end

      it 'raises error for invalid RunResult type' do
        expect {
          described_class.to_span("not a run result")
        }.to raise_error(ArgumentError, /Expected RAAF::RunResult, got String/)
      end
    end

    context 'with reasoning tokens' do
      it 'extracts reasoning tokens from output_tokens_details' do
        span = described_class.to_span(run_result, agent: agent)

        expect(span[:metadata][:reasoning_tokens]).to eq(5)
      end

      it 'handles missing reasoning tokens gracefully' do
        result_without_reasoning = RAAF::RunResult.new(
          agent_name: "TestAgent",
          messages: [{ role: "user", content: "Hello" }, { role: "assistant", content: "Hi" }],
          usage: { total_tokens: 20, input_tokens: 10, output_tokens: 10 }
        )

        span = described_class.to_span(result_without_reasoning, agent: agent)

        expect(span[:metadata]).not_to have_key(:reasoning_tokens)
      end
    end

    context 'with minimal RunResult' do
      let(:minimal_run_result) do
        RAAF::RunResult.new(
          agent_name: "MinimalAgent",
          messages: [
            { role: "user", content: "Test" },
            { role: "assistant", content: "Response" }
          ]
        )
      end

      it 'handles missing usage data' do
        span = described_class.to_span(minimal_run_result)

        expect(span[:metadata]).not_to have_key(:tokens)
        expect(span[:metadata]).not_to have_key(:input_tokens)
        expect(span[:metadata]).not_to have_key(:output_tokens)
      end

      it 'handles missing final_output' do
        span = described_class.to_span(minimal_run_result)

        expect(span[:metadata]).not_to have_key(:output)
      end

      it 'handles missing turns' do
        span = described_class.to_span(minimal_run_result)

        expect(span[:metadata]).not_to have_key(:turns)
      end
    end

    context 'parameter extraction' do
      let(:agent_with_all_params) do
        RAAF::Agent.new(
          name: "FullAgent",
          instructions: "Test",
          model: "gpt-4o",
          temperature: 0.8,
          max_tokens: 200,
          top_p: 0.9,
          frequency_penalty: 0.5,
          presence_penalty: 0.3
        )
      end

      it 'extracts all agent parameters' do
        span = described_class.to_span(run_result, agent: agent_with_all_params)

        expect(span[:parameters]).to include(
          temperature: 0.8,
          max_tokens: 200,
          top_p: 0.9,
          frequency_penalty: 0.5,
          presence_penalty: 0.3
        )
      end

      it 'only includes parameters that are set' do
        minimal_agent = RAAF::Agent.new(
          name: "MinimalAgent",
          instructions: "Test",
          model: "gpt-4o"
        )

        span = described_class.to_span(run_result, agent: minimal_agent)

        expect(span[:parameters]).to eq({})
      end
    end
  end
end
