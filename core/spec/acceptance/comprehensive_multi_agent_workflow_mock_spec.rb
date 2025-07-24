# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Comprehensive Multi-Agent Workflow with Mocks", :acceptance do
  # This test demonstrates all requested features using mocks:
  # 1. Multiple agents (3 agents)
  # 2. Handoffs between agents
  # 3. Context sharing via hooks
  # 4. Multiple tool calls per agent
  # 5. VCR recording capability
  # 6. Input and output guardrails

  let(:shared_context) { { workflow_data: {} } }

  # Custom hook for writing results back to context
  let(:context_hook) do
    Class.new do
      attr_reader :shared_context

      def initialize(shared_context)
        @shared_context = shared_context
      end

      def on_agent_start(context, _agent)
        # Load any existing context data
        context.store(:shared_data, @shared_context[:workflow_data] || {})

        # Initialize workflow data if needed
        @shared_context[:workflow_data] ||= {}
      end

      def on_tool_start(context, agent, tool, arguments = {})
        # Called when tool starts - could track tool calls here if needed
      end

      def on_tool_end(_context, _agent, tool, result)
        # Store tool results in shared context
        @shared_context[:workflow_data] ||= {}
        tool_name = tool.respond_to?(:name) ? tool.name : tool.to_s
        @shared_context[:workflow_data]["#{tool_name}_result"] = result
      end

      def on_agent_end(_context, agent, result)
        # Save agent results to shared context
        @shared_context[:workflow_data] ||= {}
        @shared_context[:workflow_data]["#{agent.name}_completed"] = true

        # result is a hash with role, content, etc, not a hash with direct access
        return unless result.is_a?(Hash) && result[:content]

        @shared_context[:workflow_data]["#{agent.name}_final_message"] = result[:content]
      end

      def on_handoff(_context, from_agent, to_agent)
        # Log handoff in shared context
        @shared_context[:workflow_data] ||= {}
        @shared_context[:workflow_data][:handoffs] ||= []
        @shared_context[:workflow_data][:handoffs] << {
          from: from_agent.name,
          to: to_agent.name,
          timestamp: Time.now
        }
      end
    end.new(shared_context)
  end

  # Mock provider that simulates agent responses with tool calls and handoffs
  let(:mock_provider) do
    provider = RAAF::Testing::MockProvider.new

    # Research agent responses - multiple tool calls
    provider.add_response(
      "I'll search for information about Ruby and AI agents",
      tool_calls: [
        {
          id: "call_1",
          type: "function",
          function: { name: "search_web", arguments: { query: "Ruby programming language" }.to_json }
        }
      ]
    )

    provider.add_response(
      "Now let me search for academic papers and statistics",
      tool_calls: [
        {
          id: "call_2",
          type: "function",
          function: { name: "search_papers", arguments: { topic: "AI agents", year: 2024 }.to_json }
        },
        {
          id: "call_3",
          type: "function",
          function: { name: "get_statistics", arguments: { category: "ai_adoption" }.to_json }
        }
      ]
    )

    provider.add_response(
      "I've gathered comprehensive research data. Let me hand this off to the analyst.",
      tool_calls: [
        {
          id: "call_4",
          type: "function",
          function: { name: "transfer_to_analysis_agent", arguments: {}.to_json }
        }
      ]
    )

    # Analysis agent responses - multiple tool calls
    provider.add_response(
      "I'll analyze the research data using multiple analytical tools",
      tool_calls: [
        {
          id: "call_5",
          type: "function",
          function: { name: "calculate_trends", arguments: { data_points: 100, metric: "adoption_rate" }.to_json }
        }
      ]
    )

    provider.add_response(
      "Let me compare datasets and generate insights",
      tool_calls: [
        {
          id: "call_6",
          type: "function",
          function: { name: "compare_data", arguments: { dataset1: "Ruby usage", dataset2: "Python usage" }.to_json }
        },
        {
          id: "call_7",
          type: "function",
          function: { name: "generate_insights", arguments: { analysis_type: "market_trends" }.to_json }
        }
      ]
    )

    provider.add_response(
      "Analysis complete. Transferring to the report writer.",
      tool_calls: [
        {
          id: "call_8",
          type: "function",
          function: { name: "transfer_to_report_writer", arguments: {}.to_json }
        }
      ]
    )

    # Report writer responses - multiple tool calls
    provider.add_response(
      "I'll format the report sections based on the research and analysis",
      tool_calls: [
        {
          id: "call_9",
          type: "function",
          function: { name: "format_section", arguments: { title: "Executive Summary", content: "Overview of findings" }.to_json }
        },
        {
          id: "call_10",
          type: "function",
          function: { name: "create_summary", arguments: { key_points: "Ruby growth, AI adoption trends" }.to_json }
        }
      ]
    )

    provider.add_response(
      "Adding citations and finalizing the report",
      tool_calls: [
        {
          id: "call_11",
          type: "function",
          function: { name: "add_citations", arguments: { source_type: "academic", count: 5 }.to_json }
        }
      ]
    )

    provider.add_response(
      "## Comprehensive Report on Ruby and AI Agents\n\n### Executive Summary\nBased on extensive research and analysis...\n\n### Key Findings\n1. Ruby adoption: 2.1% market share\n2. AI agent frameworks growing 67% YoY\n3. Enterprise adoption at 35%\n\n### Recommendations\nContinue investing in Ruby-based AI agent frameworks."
    )

    provider
  end

  # Research Agent with tools
  let(:research_agent) do
    agent = RAAF::Agent.new(
      name: "ResearchAgent",
      instructions: "You are a research specialist. Gather comprehensive information using all available tools before handing off to the analyst.",
      model: "gpt-4o"
    )

    # Tool 1: Search web
    search_web = lambda do |_query:|
      "Ruby is a dynamic programming language created by Yukihiro Matsumoto in 1995. Latest version: 3.3.0"
    end

    # Tool 2: Search papers
    search_papers = lambda do |topic:, _year: nil|
      "Found 15 academic papers on '#{topic}'. Top paper: 'Advances in #{topic}' with 523 citations."
    end

    # Tool 3: Get statistics
    get_statistics = lambda do |category:|
      { "ai_adoption" => { enterprise: "35%", startups: "67%", research: "89%" } }[category].to_h
    end

    agent.add_tool(RAAF::FunctionTool.new(search_web,
                                          name: "search_web",
                                          description: "Search the web for information",
                                          parameters: {
                                            type: "object",
                                            properties: {
                                              query: { type: "string", description: "Search query" }
                                            },
                                            required: ["query"]
                                          }))

    agent.add_tool(RAAF::FunctionTool.new(search_papers,
                                          name: "search_papers",
                                          description: "Search academic papers",
                                          parameters: {
                                            type: "object",
                                            properties: {
                                              topic: { type: "string" },
                                              year: { type: "integer" }
                                            },
                                            required: ["topic"]
                                          }))

    agent.add_tool(RAAF::FunctionTool.new(get_statistics,
                                          name: "get_statistics",
                                          description: "Get statistics",
                                          parameters: {
                                            type: "object",
                                            properties: {
                                              category: { type: "string" }
                                            },
                                            required: ["category"]
                                          }))

    agent
  end

  # Analysis Agent with tools
  let(:analysis_agent) do
    agent = RAAF::Agent.new(
      name: "AnalysisAgent",
      instructions: "You are a data analyst. Analyze the research data using your tools.",
      model: "gpt-4o"
    )

    calculate_trends = lambda do |_data_points:, metric:|
      "Trend analysis for #{metric}: Positive growth of 15%"
    end

    compare_data = lambda do |dataset1:, dataset2:|
      "#{dataset1} outperforms #{dataset2} by 23%"
    end

    generate_insights = lambda do |analysis_type:|
      "Key insight: #{analysis_type} analysis reveals emerging patterns"
    end

    agent.add_tool(RAAF::FunctionTool.new(calculate_trends,
                                          name: "calculate_trends",
                                          description: "Calculate trends",
                                          parameters: {
                                            type: "object",
                                            properties: {
                                              data_points: { type: "integer" },
                                              metric: { type: "string" }
                                            },
                                            required: %w[data_points metric]
                                          }))

    agent.add_tool(RAAF::FunctionTool.new(compare_data,
                                          name: "compare_data",
                                          description: "Compare datasets",
                                          parameters: {
                                            type: "object",
                                            properties: {
                                              dataset1: { type: "string" },
                                              dataset2: { type: "string" }
                                            },
                                            required: %w[dataset1 dataset2]
                                          }))

    agent.add_tool(RAAF::FunctionTool.new(generate_insights,
                                          name: "generate_insights",
                                          description: "Generate insights",
                                          parameters: {
                                            type: "object",
                                            properties: {
                                              analysis_type: { type: "string" }
                                            },
                                            required: ["analysis_type"]
                                          }))

    agent
  end

  # Report Writer Agent with tools
  let(:report_writer_agent) do
    agent = RAAF::Agent.new(
      name: "ReportWriter",
      instructions: "You are a report writer. Create a comprehensive report using the data.",
      model: "gpt-4o"
    )

    format_section = lambda do |title:, content:|
      "## #{title}\n\n#{content}"
    end

    create_summary = lambda do |key_points:|
      "Executive Summary: #{key_points}"
    end

    add_citations = lambda do |source_type:, count:|
      "Added #{count} #{source_type} citations"
    end

    agent.add_tool(RAAF::FunctionTool.new(format_section,
                                          name: "format_section",
                                          description: "Format section",
                                          parameters: {
                                            type: "object",
                                            properties: {
                                              title: { type: "string" },
                                              content: { type: "string" }
                                            },
                                            required: %w[title content]
                                          }))

    agent.add_tool(RAAF::FunctionTool.new(create_summary,
                                          name: "create_summary",
                                          description: "Create summary",
                                          parameters: {
                                            type: "object",
                                            properties: {
                                              key_points: { type: "string" }
                                            },
                                            required: ["key_points"]
                                          }))

    agent.add_tool(RAAF::FunctionTool.new(add_citations,
                                          name: "add_citations",
                                          description: "Add citations",
                                          parameters: {
                                            type: "object",
                                            properties: {
                                              source_type: { type: "string" },
                                              count: { type: "integer" }
                                            },
                                            required: %w[source_type count]
                                          }))

    agent
  end

  # Guardrails
  let(:input_guardrail) do
    RAAF::Guardrails::InputGuardrail.new(
      instructions: "Block sensitive data"
    ) do |input|
      "Input blocked: Contains sensitive information" if input =~ /\b\d{4}[\s-]?\d{4}[\s-]?\d{4}[\s-]?\d{4}\b/
    end
  end

  let(:output_guardrail) do
    RAAF::Guardrails::OutputGuardrail.new(
      instructions: "Ensure professional language"
    ) do |output|
      output.gsub(/\b(damn|hell)\b/i, "[removed]")
    end
  end

  before do
    # Set up handoffs
    research_agent.add_handoff(analysis_agent)
    analysis_agent.add_handoff(report_writer_agent)
  end

  describe "complete workflow with all features" do
    it "demonstrates all requested features with mocks", :vcr do
      VCR.use_cassette("mock_comprehensive_workflow") do
        # Create runner with mock provider
        runner = RAAF::Runner.new(
          agent: research_agent,
          provider: mock_provider
        )

        # Add guardrails
        [research_agent, analysis_agent, report_writer_agent].each do |agent|
          agent.add_input_guardrail(input_guardrail)
          agent.add_output_guardrail(output_guardrail)
        end

        # Execute with hooks and all agents
        result = runner.run(
          "Research Ruby and AI agents, analyze trends, create report",
          hooks: context_hook,
          agents: [research_agent, analysis_agent, report_writer_agent]
        )

        # Verify all features
        expect(result).to be_a(RAAF::RunResult)

        # Verify handoffs (allowing for duplicate calls)
        expect(shared_context[:workflow_data][:handoffs]).not_to be_nil
        expect(shared_context[:workflow_data][:handoffs].length).to be >= 2

        # Check unique handoffs
        unique_handoffs = shared_context[:workflow_data][:handoffs].map { |h| "#{h[:from]}->#{h[:to]}" }.uniq
        expect(unique_handoffs).to include("ResearchAgent->AnalysisAgent")
        expect(unique_handoffs).to include("AnalysisAgent->ReportWriter")

        # Verify at least the final agent completed
        expect(shared_context[:workflow_data]["ReportWriter_completed"]).to be true

        # Verify multiple tools were called per agent
        tool_results = shared_context[:workflow_data].keys.select { |k| k.end_with?("_result") }
        expect(tool_results).to include("search_web_result")
        expect(tool_results).to include("search_papers_result")
        expect(tool_results).to include("get_statistics_result")
        expect(tool_results).to include("calculate_trends_result")
        expect(tool_results).to include("compare_data_result")
        expect(tool_results).to include("generate_insights_result")
        expect(tool_results).to include("format_section_result")
        expect(tool_results).to include("create_summary_result")
        expect(tool_results).to include("add_citations_result")

        # Verify final report
        final_message = result.messages.last[:content]
        # The mock provider's last response contains the comprehensive report
        expect(result.messages).not_to be_empty

        # Find the report writer's final message which should contain the report
        report_messages = result.messages.select { |m| m[:role] == "assistant" && m[:content]&.include?("Comprehensive Report") }
        expect(report_messages).not_to be_empty

        report_content = report_messages.last[:content]
        expect(report_content).to include("Executive Summary")
        expect(report_content).to include("Key Findings")

        # Output results
        puts "\n=== WORKFLOW SUMMARY ==="
        puts "Total handoffs: #{shared_context[:workflow_data][:handoffs].length}"
        puts "Tools called: #{tool_results.length}"
        puts "Final report length: #{final_message.length} chars"
        puts "========================\n"
      end
    end

    it "blocks sensitive input with guardrails" do
      runner = RAAF::Runner.new(
        agent: research_agent,
        provider: mock_provider
      )

      research_agent.add_input_guardrail(input_guardrail)

      expect do
        runner.run("Research credit card 4111-1111-1111-1111")
      end.to raise_error(/Input blocked: Contains sensitive information/)
    end

    it "filters output with guardrails" do
      # Create a mock that returns content with profanity
      provider = RAAF::Testing::MockProvider.new
      provider.add_response("This is a damn good analysis of Ruby")

      runner = RAAF::Runner.new(
        agent: research_agent,
        provider: provider
      )

      research_agent.add_output_guardrail(output_guardrail)

      result = runner.run("Test message")
      expect(result.messages.last[:content]).to include("[removed] good analysis")
    end
  end
end
